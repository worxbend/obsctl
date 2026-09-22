require "../obs/state/obs_snapshot"
require "../domain/volume"
require "../runtime/logger"
require "./theme"
require "./anim"
require "./meter"
require "./localization"
require "./scene_picker"
require "./scene_profiles"
require "./scene_profile_list"
require "./model/anim_clock"
require "./model/command_palette_state"
require "./model/dashboard_state"
require "./model/focus_panel"
require "./model/focus_state"
require "./model/list_cursor"
require "./model/log_entry"
require "./model/logs_pane_state"
require "./model/scene_picker_state"
require "./model/scene_profile_editor_state"
require "./model/scene_profile_list_state"
require "./model/settings_state"
require "./model/stats_pane_state"
require "./model/status_state"
require "./model/view"

module Obsctl
  module TUI
    # Everything the dashboard draws, composed from per-surface state objects
    # rather than held as one flat bag.
    #
    # The composition rule: state lives on the sub-state that owns the
    # surface it belongs to. `DashboardState` holds what the daemon reported
    # and every list derived from it; `StatsPaneState` the meters and
    # sparklines; `LogsPaneState` the log ring; `StatusState` the status line
    # and the daemon-connection flag; `SettingsState` the theme, the display
    # preferences and the settings view; `FocusState` which panel is pointed
    # at and where each panel's cursor sits; and each modal overlay has a
    # state object of its own, the way `CommandPaletteState` always has.
    # What stays on the root is what genuinely spans surfaces: the animation
    # clock that three sub-states stamp frames against, the pending key
    # sequence that every action ends, and the coordinators that cannot live
    # on either side alone -- adopting a snapshot re-seeks cursors the focus
    # and picker states hold, clamping needs every list's row count, and the
    # move commands need the focused panel's.
    #
    # The delegations at the bottom are the read surface the widgets and the
    # spec suite share. A delegation hides nothing: `model.scenes` answers
    # what `model.dashboard.scenes` answers, and the caching rule lives in
    # one place. Callers doing surface-specific work reach into the
    # sub-state directly -- the dispatcher drives the modal states and the
    # settings view, the pane widgets read the panes -- so the sub-states
    # are the working interface, not an implementation detail behind a
    # façade.
    #
    # Three fibers write to the model: the run loop (keys, mouse and the
    # refresh tick), the debounce fiber that settles a volume edit 120 ms
    # after the last keypress, and the fiber that reads pushed events off
    # the daemon socket. None of them locks, and none needs to: Crystal
    # schedules fibers cooperatively on a single thread here, so a fiber
    # keeps the model to itself until it reaches a point where it yields --
    # an I/O wait, a `sleep`, or a channel operation. What is not safe is
    # leaving the model half-updated *across* such a point, so each of the
    # three does its writes in one uninterrupted run.
    class Model
      getter dashboard : DashboardState
      getter stats_pane : StatsPaneState
      getter logs_pane : LogsPaneState
      getter status : StatusState
      getter settings : SettingsState
      getter focus_state : FocusState
      getter scene_picker : ScenePickerState
      property command_palette : CommandPaletteState
      property scene_profile_editor : SceneProfileEditorState
      property scene_profile_list : SceneProfileListState

      # Owned by the root rather than by any one sub-state because three of
      # them stamp frames against it -- meter peaks, the scene flash, the
      # typed-out status line -- and a struct copied into a sub-state would
      # stop ticking with the root's.
      getter anim : AnimClock
      # Keys of a multi-key binding pressed so far, e.g. `<leader>f`.
      # Non-empty means the which-key menu is open and the next key completes
      # or cancels. Stays on the root because every action ends the sequence,
      # whichever surface the action belonged to.
      property pending_sequence : String

      def initialize(theme : Theme = Theme.default, show_icons : Bool = true, advanced_ui : Bool = true, command_palette_prefix : String = "/", locale : String = "en")
        @dashboard = DashboardState.new
        @stats_pane = StatsPaneState.new
        @logs_pane = LogsPaneState.new
        @status = StatusState.new
        @settings = SettingsState.new(theme: theme, show_icons: show_icons, advanced_ui: advanced_ui, command_palette_prefix: command_palette_prefix, locale: locale)
        @focus_state = FocusState.new
        @scene_picker = ScenePickerState.new
        @command_palette = CommandPaletteState.new
        @scene_profile_editor = SceneProfileEditorState.new
        @scene_profile_list = SceneProfileListState.new
        @anim = AnimClock.new
        @pending_sequence = ""
      end

      # Adopts a new snapshot, keeping the scene cursors on the scenes they
      # were pointing at.
      #
      # The cursors are indexes into the visible scene list, and a snapshot
      # can change what that list contains -- a scene profile switched on
      # here, by the CLI, or by a second dashboard; a scene added or removed
      # in OBS. Clamping alone keeps an index in range but not on the same
      # scene, so the highlight would slide to a neighbour and the next Enter
      # would tell OBS to switch to whatever it landed on. Re-seeking by name
      # is what stops a filter change from becoming an unasked-for scene
      # change.
      #
      # A cursor whose scene the new snapshot no longer shows has nowhere to
      # go and keeps the clamped position.
      #
      # This is the coordinator, not the storage: `DashboardState#adopt`
      # swaps and invalidates, and the cursors belong to the focus and picker
      # states. Neither half is optional, which is why the assignment lives
      # here rather than as a setter on either sub-state.
      def snapshot=(snapshot : OBS::State::ObsSnapshot?) : OBS::State::ObsSnapshot?
        focused = focused_scene.try(&.name)
        picked = dashboard.scenes[scene_picker.cursor]?.try(&.name)
        dashboard.adopt(snapshot)
        retarget_scene_cursors(focused, picked)
        snapshot
      end

      # Re-seeks the two scene cursors onto the named scenes, and clamps
      # whatever is left over. `snapshot=` is the caller that matters; see the
      # reasoning there.
      def retarget_scene_cursors(scene_name : String?, picker_name : String?) : Nil
        clamp_cursors
        visible = dashboard.scenes
        if scene_name && (index = visible.index { |scene| scene.name == scene_name })
          focus_state.set_cursor(FocusPanel::Scenes, index)
        end
        if picker_name && (index = visible.index { |scene| scene.name == picker_name })
          scene_picker.cursor = index
        end
      end

      # Pulls every cursor back inside its panel after the lists change, so a
      # scene deleted in OBS cannot leave a cursor pointing past the end. The
      # modal cursors ride along: one clamp per overlay, each against the list
      # that overlay actually shows.
      def clamp_cursors
        FocusPanel.values.each do |panel|
          focus_state.clamp(panel, dashboard.item_count(panel))
        end
        scene_picker.clamp(dashboard.scenes.size)
        # Against `all_scenes`, not `scenes`: the editor is the one surface
        # that lists hidden scenes too, so clamping it to the visible list
        # would put its cursor out of reach of exactly the rows it exists to
        # unhide.
        scene_profile_editor.clamp(dashboard.all_scenes.size)
        # Against the row count, which is one more than the number of
        # profiles: the "show every scene" row is a row like any other here.
        scene_profile_list.clamp(dashboard.scene_profile_list_entries.size)
      end

      def move_up
        move_by(-1)
      end

      def move_down
        move_by(1)
      end

      def move_by(delta : Int32)
        move_to(cursor + delta)
      end

      def move_top
        move_to(0)
      end

      def move_bottom
        move_to(item_count - 1)
      end

      # The count-aware half of the move: the focused panel's row count lives
      # on the dashboard, so the clamp rule that needs it is composed here
      # rather than on either sub-state.
      def move_to(index : Int32)
        focus_state.move_to(focus, index, item_count)
      end

      # How many rows the focused panel has. The exhaustive `in` that keeps a
      # fifth panel a compile error lives on `DashboardState#item_count`.
      def item_count(panel : FocusPanel = focus) : Int32
        dashboard.item_count(panel)
      end

      def focused_scene : OBS::State::SceneState?
        dashboard.scenes[scene_cursor]?
      end

      def focused_audio : OBS::State::AudioState?
        dashboard.audio_inputs[audio_cursor]?
      end

      # Appends this frame's readings to the sparkline histories; the
      # sampling rule lives on `StatsPaneState#record_sample`.
      def record_metric_sample
        stats_pane.record_sample(dashboard.stats, dashboard.stream_bitrate_kbps)
      end

      # The clock-boundary half of the meter API: the peaks are stored as
      # frames, so the current frame has to arrive with the reading.
      def record_meter_level(input_name : String, level : Float64) : Nil
        stats_pane.record_meter_level(input_name, level, anim)
      end

      def meter_peak(input_name : String) : Float64?
        stats_pane.meter_peak(input_name, anim)
      end

      def set_last_result(message : String)
        status.set_last_result(message, anim)
      end

      def revealed_last_result(characters_per_frame : Int32) : String?
        status.revealed_last_result(anim, characters_per_frame)
      end

      # -- Delegations -------------------------------------------------------
      #
      # The shared read surface, answered by the sub-state that owns it. What
      # earns a place here is call volume, not importance: the widgets paint
      # with `theme` and `symbol` on every span, and the spec suite drives the
      # model through these names. Surface-specific work reaches into the
      # sub-state directly instead -- see the class comment.

      # The appearance vocabulary: what every widget paints with.
      def theme : Theme
        settings.theme
      end

      def theme=(theme : Theme)
        settings.theme = theme
      end

      def show_icons : Bool
        settings.show_icons
      end

      def show_icons=(show_icons : Bool)
        settings.show_icons = show_icons
      end

      def advanced_ui : Bool
        settings.advanced_ui
      end

      def advanced_ui=(advanced_ui : Bool)
        settings.advanced_ui = advanced_ui
      end

      def locale : String
        settings.locale
      end

      def command_palette_prefix : String
        settings.command_palette_prefix
      end

      def rich_ui? : Bool
        settings.rich_ui?
      end

      def symbol(rich : String, fallback : String) : String
        settings.symbol(rich, fallback)
      end

      # The settings view's own state.
      def view : View
        settings.view
      end

      def view=(view : View)
        settings.view = view
      end

      def settings_cursor : Int32
        settings.settings_cursor
      end

      def settings_cursor=(settings_cursor : Int32)
        settings.settings_cursor = settings_cursor
      end

      def theme_preview_origin : Theme?
        settings.theme_preview_origin
      end

      def theme_preview_origin=(theme_preview_origin : Theme?)
        settings.theme_preview_origin = theme_preview_origin
      end

      # Which panel is pointed at.
      def focus : FocusPanel
        focus_state.focus
      end

      def focus=(focus : FocusPanel)
        focus_state.focus = focus
      end

      def cursor(panel : FocusPanel = focus) : Int32
        focus_state.cursor(panel)
      end

      def set_cursor(panel : FocusPanel, index : Int32) : Nil
        focus_state.set_cursor(panel, index)
      end

      # The per-panel cursor names the widgets and the hit test read.
      {% for panel, name in {Scenes: "scene", Audio: "audio", Profiles: "profile", Collections: "collection"} %}
        def {{ name.id }}_cursor : Int32
          focus_state.{{ name.id }}_cursor
        end

        def {{ name.id }}_cursor=(index : Int32) : Nil
          focus_state.{{ name.id }}_cursor = index
        end
      {% end %}

      # What the daemon reported, and the lists derived from it.
      def snapshot : OBS::State::ObsSnapshot?
        dashboard.snapshot
      end

      def scenes : Array(OBS::State::SceneState)
        dashboard.scenes
      end

      def all_scenes : Array(OBS::State::SceneState)
        dashboard.all_scenes
      end

      def audio_inputs : Array(OBS::State::AudioState)
        dashboard.audio_inputs
      end

      def profiles : Array(String)
        dashboard.profiles
      end

      def current_profile : String?
        dashboard.current_profile
      end

      def scene_collections : Array(String)
        dashboard.scene_collections
      end

      def current_scene_collection : String?
        dashboard.current_scene_collection
      end

      def current_scene : String?
        dashboard.current_scene
      end

      def obs_connected? : Bool
        dashboard.obs_connected?
      end

      def streaming? : Bool
        dashboard.streaming?
      end

      def recording? : Bool
        dashboard.recording?
      end

      def stats : OBS::State::ObsStats?
        dashboard.stats
      end

      def stream_bitrate_kbps : Float64?
        dashboard.stream_bitrate_kbps
      end

      def stream_duration_ms : Int64?
        dashboard.stream_duration_ms
      end

      def record_duration_ms : Int64?
        dashboard.record_duration_ms
      end

      def scene_profiles : SceneProfiles
        dashboard.scene_profiles
      end

      def scene_picker_entries : Array(ScenePicker::Entry)
        dashboard.scene_picker_entries
      end

      def scene_profile_list_entries : Array(SceneProfileList::Entry)
        dashboard.scene_profile_list_entries
      end

      def scene_flash : Tuple(String, UInt64)?
        dashboard.scene_flash
      end

      def scene_flash=(scene_flash : Tuple(String, UInt64)?)
        dashboard.scene_flash = scene_flash
      end

      # Applies an optimistic volume value so rapid keyboard changes render
      # immediately while the debounced OBS command is still pending.
      def preview_audio_volume(input_name : String, percent : Int32) : Nil
        dashboard.preview_audio_volume(input_name, percent)
      end

      # Forgets the optimistic value for one input, because the command that
      # carried it has finished and the daemon's own snapshots are now the
      # better answer.
      def settle_volume(input_name : String) : Nil
        dashboard.settle_volume(input_name)
      end

      # The meters and sparklines.
      def meter_levels : Hash(String, Float64)
        stats_pane.meter_levels
      end

      def cpu_history : Array(Float64)
        stats_pane.cpu_history
      end

      def cpu_history=(cpu_history : Array(Float64))
        stats_pane.cpu_history = cpu_history
      end

      def bitrate_history : Array(Float64)
        stats_pane.bitrate_history
      end

      def bitrate_history=(bitrate_history : Array(Float64))
        stats_pane.bitrate_history = bitrate_history
      end

      def fps_history : Array(Float64)
        stats_pane.fps_history
      end

      def fps_history=(fps_history : Array(Float64))
        stats_pane.fps_history = fps_history
      end

      # The log ring.
      def logs : Array(LogEntry)
        logs_pane.entries
      end

      def push_log(entry : LogEntry)
        logs_pane.push(entry)
      end

      # The status line and the daemon-connection flag.
      def last_result : String?
        status.last_result
      end

      def last_result=(last_result : String?)
        status.last_result = last_result
      end

      def last_result_frame : UInt64
        status.last_result_frame
      end

      def connected_to_daemon : Bool
        status.connected_to_daemon
      end

      def connected_to_daemon=(connected_to_daemon : Bool)
        status.connected_to_daemon = connected_to_daemon
      end

      # The scene picker overlay, under the names it had as plain properties.
      def scene_picker_active : Bool
        scene_picker.active
      end

      def scene_picker_active=(scene_picker_active : Bool)
        scene_picker.active = scene_picker_active
      end

      def scene_picker_cursor : Int32
        scene_picker.cursor
      end

      def scene_picker_cursor=(scene_picker_cursor : Int32)
        scene_picker.cursor = scene_picker_cursor
      end
    end
  end
end
