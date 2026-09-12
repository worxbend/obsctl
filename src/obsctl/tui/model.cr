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

module Obsctl
  module TUI
    enum FocusPanel
      Scenes
      Audio
      Profiles
      Collections

      def left : self
        audio? ? Scenes : (collections? ? Profiles : self)
      end

      def right : self
        scenes? ? Audio : (profiles? ? Collections : self)
      end

      def up : self
        profiles? ? Scenes : (collections? ? Audio : self)
      end

      def down : self
        scenes? ? Profiles : (audio? ? Collections : self)
      end
    end

    enum View
      Main
      Settings
    end

    struct AnimClock
      property frame : UInt64

      def initialize(@frame = 0_u64)
      end

      def tick
        @frame &+= 1
      end

      def pulse(period_ticks : UInt64) : Float32
        period = {period_ticks, 1_u64}.max
        phase = (@frame % period).to_f32 / period.to_f32
        Math.sin(phase * Math::TAU.to_f32) * 0.5_f32 + 0.5_f32
      end

      def spinner(frames : Indexable(String), ticks_per_frame : UInt64 = 1_u64) : String
        return "" if frames.empty?
        step = {ticks_per_frame, 1_u64}.max
        frames[((@frame // step) % frames.size).to_i]
      end
    end

    record LogEntry,
      level : Runtime::LogLevel,
      message : String,
      code : String? = nil,
      timestamp : Time = Time.utc

    class CommandPaletteState
      property active : Bool
      property input : String
      property completions : Array(String)
      property completion_index : Int32?

      def initialize(@active = false, @input = "", @completions = [] of String, @completion_index = nil)
      end

      def cycle_next
        return if @completions.empty?
        index = @completion_index
        next_index = index ? (index + 1) % @completions.size : 0
        @completion_index = next_index
        @input = @completions[next_index]
      end

      def cycle_previous
        return if @completions.empty?
        next_index = case index = @completion_index
                     when Nil then @completions.size - 1
                     when 0   then @completions.size - 1
                     else          index - 1
                     end
        @completion_index = next_index
        @input = @completions[next_index]
      end
    end

    # Moving a cursor through a list, and pulling it back inside one.
    #
    # The three modal cursors -- the scene picker, the scene-profile list and
    # the scene-profile editor -- each wrote the move out longhand,
    # `{cursor - 1, 0}.max` one way and `{cursor + 1, {count - 1, 0}.max}.min`
    # the other, and `Model#clamp_cursors` wrote the clamp out four times over.
    # Named once here, each site says which list it is moving through instead
    # of restating what moving through a list means.
    #
    # `moved` is deliberately asymmetric: going up stops at zero without
    # consulting `count`, while going down stops at the last row. A cursor
    # sitting past the end -- which is what a list that has just shrunk leaves
    # behind, until the next `clamp_cursors` -- therefore keeps its place when
    # the user moves up, exactly as it did before. Folding the two directions
    # into one `clamp` would read more tidily and would quietly change that.
    #
    # The dashboard panels' own `move_to` is a different rule and stays where
    # it is: it clamps both directions, because `G` and a half-page jump have
    # to land on the last row rather than past it.
    module ListCursor
      def self.moved(cursor : Int32, delta : Int32, count : Int32) : Int32
        return {cursor + delta, 0}.max if delta < 0

        {cursor + delta, {count - 1, 0}.max}.min
      end

      # `count - 1` floored at zero, so an empty list parks the cursor on row
      # zero instead of on -1.
      def self.clamped(cursor : Int32, count : Int32) : Int32
        cursor.clamp(0, {count - 1, 0}.max)
      end

      # Mixed into the two modal states below, which each hold their cursor as
      # `@cursor`. The cursors that are plain properties on `Model` reach the
      # same rule through `ListCursor.moved` and `.clamped` instead.
      def move(delta : Int32, count : Int32) : Nil
        @cursor = ListCursor.moved(@cursor, delta, count)
      end

      def clamp(count : Int32) : Nil
        @cursor = ListCursor.clamped(@cursor, count)
      end
    end

    # What the scene-profile editor is holding while it is open.
    #
    # The draft is deliberately separate from `Model#scene_profiles`: toggling a
    # scene has to repaint immediately, but must not change what the dashboard
    # shows until the user saves, and Esc has to be able to throw the whole
    # draft away. `name` is empty for a draft nobody has named yet, which is
    # what turns Enter into a prompt instead of a save.
    class SceneProfileEditorState
      include ListCursor

      property active : Bool
      property cursor : Int32
      property name : String
      property hidden : Set(String)
      # True while the user is typing a name. The modal's keys mean different
      # things in the two sub-modes -- `t` toggles a scene in one and types a
      # letter in the other -- so the mode has to be part of the state rather
      # than inferred.
      property naming : Bool
      property name_input : String
      # The saved profile this draft was loaded from, or nil for a draft that is
      # not based on one.
      #
      # This is what makes renaming possible: saving under a different name
      # renames that profile in place instead of leaving the original behind
      # beside a copy of it.
      property origin_name : String?

      def initialize(@active = false, @cursor = 0, @name = "", @hidden = Set(String).new, @naming = false, @name_input = "", @origin_name = nil)
      end
    end

    # What the scene-profile list is holding while it is open.
    #
    # A class of its own rather than two properties on the model, the way the
    # scene picker does it, because this modal has a sub-mode: `confirming` is
    # a delete waiting for its second press, during which the keys mean
    # different things -- the same reason `SceneProfileEditorState` carries
    # `naming` rather than inferring it.
    class SceneProfileListState
      include ListCursor

      property active : Bool
      property cursor : Int32
      # True after the first `d`, while a delete waits for the second press.
      property confirming : Bool

      def initialize(@active = false, @cursor = 0, @confirming = false)
      end
    end

    # Everything the dashboard draws, in one mutable object.
    #
    # Three fibers write to it: the run loop (keys, mouse and the refresh
    # tick), the debounce fiber that settles a volume edit 120 ms after the
    # last keypress, and the fiber that reads pushed events off the daemon
    # socket. None of them locks, and none needs to: Crystal schedules fibers
    # cooperatively on a single thread here, so a fiber keeps the model to
    # itself until it reaches a point where it yields -- an I/O wait, a
    # `sleep`, or a channel operation. What is not safe is leaving the model
    # half-updated *across* such a point, so each of the three does its writes
    # in one uninterrupted run.
    class Model
      MAX_LOG_ENTRIES = 200

      # How many samples each sparkline keeps. The stats widgets plot these at
      # one column per sample, so this is also the widest a sparkline can be
      # before it starts repeating; 32 covers the panel at any usable terminal
      # width without holding history nothing draws.
      METRIC_HISTORY_SAMPLES = 32

      getter snapshot : OBS::State::ObsSnapshot?
      property logs : Array(LogEntry)
      property command_palette : CommandPaletteState
      property last_result : String?
      property last_result_frame : UInt64
      property connected_to_daemon : Bool
      property focus : FocusPanel
      # One cursor per panel, keyed by the panel it belongs to.
      #
      # These were four separate fields, which made every operation over "the
      # cursor of whichever panel is focused" a four-armed `case` on
      # `FocusPanel` — one to read it, one to move it, one to clamp them all,
      # and one more in the dispatcher to place it after a click. Adding a
      # fifth panel meant finding every one of them, and missing one failed
      # quietly, as a cursor that simply stopped responding in that panel.
      # Keyed by the enum, each of those becomes a lookup.
      #
      # The `scene_cursor`, `audio_cursor`, `profile_cursor` and
      # `collection_cursor` accessors below are unchanged for callers; they
      # now read and write this map.
      @cursors : Hash(FocusPanel, Int32)
      # Volume edits the user has made but the daemon has not acknowledged yet.
      #
      # A volume keypress paints the new level immediately and only sends the
      # OBS command once the keys stop coming, so for up to that debounce
      # window the screen holds a level the daemon has never heard of. The
      # daemon pushes a fresh snapshot every couple of seconds and after any
      # other client's command, and such a push carries the *old* level. This
      # map is what lets `snapshot=` tell "the daemon disagrees" apart from
      # "the daemon has not been told yet", instead of relying on the push
      # happening to miss the debounce window.
      @pending_volumes : Hash(String, Int32)
      # Derived collections are cached until the snapshot or pending preview
      # they depend on changes, so the render loop can ask for them many times
      # per frame without rebuilding the same arrays each time.
      @audio_inputs_cache : Array(OBS::State::AudioState)?
      @scenes_cache : Array(OBS::State::SceneState)?
      @scene_profiles_cache : SceneProfiles?
      @scene_picker_entries_cache : Array(ScenePicker::Entry)?
      @scene_profile_list_entries_cache : Array(SceneProfileList::Entry)?
      property meter_levels : Hash(String, Float64)
      # The highest point each meter has reached and the frame it reached it
      # on. Storing the frame rather than decaying the value every tick keeps
      # the peak marker a pure function of the clock, so nothing has to run
      # between renders for it to fall.
      property meter_peaks : Hash(String, Tuple(Float64, UInt64))
      property cpu_history : Array(Float64)
      property bitrate_history : Array(Float64)
      property fps_history : Array(Float64)
      property anim : AnimClock
      property scene_flash : Tuple(String, UInt64)?
      property view : View
      property theme : Theme
      property show_icons : Bool
      property advanced_ui : Bool
      property command_palette_prefix : String
      property locale : String
      property settings_cursor : Int32
      property theme_preview_origin : Theme?
      # Keys of a multi-key binding pressed so far, e.g. `<leader>f`. Non-empty
      # means the which-key menu is open and the next key completes or cancels.
      property pending_sequence : String
      # True while the scene picker overlay is open, during which it captures
      # every key.
      property scene_picker_active : Bool
      # The picker keeps its own cursor rather than borrowing `scene_cursor`,
      # so opening it does not move the dashboard's selection out from under
      # whichever panel is focused, and closing it without picking leaves the
      # dashboard exactly as it was.
      property scene_picker_cursor : Int32
      property scene_profile_editor : SceneProfileEditorState
      property scene_profile_list : SceneProfileListState

      def initialize(@theme = Theme.default, @show_icons = true, @advanced_ui = true, @command_palette_prefix = "/", @locale = "en")
        @snapshot = nil
        @logs = [] of LogEntry
        @command_palette = CommandPaletteState.new
        @last_result = nil
        @last_result_frame = 0_u64
        @connected_to_daemon = false
        @focus = FocusPanel::Scenes
        @cursors = FocusPanel.values.to_h { |panel| {panel, 0} }
        @pending_volumes = {} of String => Int32
        @audio_inputs_cache = nil
        @scenes_cache = nil
        @scene_profiles_cache = nil
        @scene_picker_entries_cache = nil
        @scene_profile_list_entries_cache = nil
        @meter_levels = {} of String => Float64
        @meter_peaks = {} of String => Tuple(Float64, UInt64)
        @cpu_history = [] of Float64
        @bitrate_history = [] of Float64
        @fps_history = [] of Float64
        @anim = AnimClock.new
        @scene_flash = nil
        @view = View::Main
        @settings_cursor = 0
        @theme_preview_origin = nil
        @pending_sequence = ""
        @scene_picker_active = false
        @scene_picker_cursor = 0
        @scene_profile_editor = SceneProfileEditorState.new
        @scene_profile_list = SceneProfileListState.new
      end

      # The scene picker's rows, cached until the snapshot changes.
      #
      # Input resolution, the widget and the hit test all ask for them during
      # one frame, so caching keeps that frame from rebuilding the same labels
      # several times while still invalidating before the next snapshot can
      # change which scene a label points at.
      def scene_picker_entries : Array(ScenePicker::Entry)
        @scene_picker_entries_cache ||= ScenePicker.entries(scenes)
      end

      # Cached for the same reason `scene_picker_entries` is: several callers
      # need one frame-stable answer, and only a fresh snapshot can make that
      # answer stale.
      def scene_profile_list_entries : Array(SceneProfileList::Entry)
        @scene_profile_list_entries_cache ||= SceneProfileList.entries(scene_profiles)
      end

      def rich_ui? : Bool
        @show_icons && @advanced_ui
      end

      def symbol(rich : String, fallback : String) : String
        rich_ui? ? rich : fallback
      end

      # Every scene the daemon reported, hidden ones included. The scene-profile
      # editor lists these; everything else on the dashboard uses `scenes`.
      def all_scenes : Array(OBS::State::SceneState)
        @snapshot.try(&.scenes) || [] of OBS::State::SceneState
      end

      # The scenes the dashboard draws.
      #
      # One `reject`, because the daemon has already done the deciding: it
      # resolves the active profile against the per-scene `hidden` flags -- an
      # active profile replaces those flags rather than adding to them -- and
      # ships the answer as `hidden` on each scene. The dashboard asking the
      # same question again is exactly how a client ends up disagreeing with
      # the daemon about what should be on screen.
      def scenes : Array(OBS::State::SceneState)
        @scenes_cache ||= all_scenes.reject(&.hidden)
      end

      # The saved scene profiles the daemon reported, and which one is in
      # effect. Read from the snapshot rather than from the config file so that
      # the dashboard, the CLI and a second dashboard all see one answer, and so
      # that a profile saved anywhere shows up here without a reload.
      def scene_profiles : SceneProfiles
        @scene_profiles_cache ||= begin
          if snapshot = @snapshot
            SceneProfiles.new(
              snapshot.scene_profiles.map { |profile| SceneProfile.new(profile.name, profile.hidden.to_set) },
              snapshot.active_scene_profile
            )
          else
            SceneProfiles.empty
          end
        end
      end

      def audio_inputs : Array(OBS::State::AudioState)
        @audio_inputs_cache ||= begin
          if snapshot = @snapshot
            with_pending_volumes(snapshot.audio_inputs)
          else
            [] of OBS::State::AudioState
          end
        end
      end

      def profiles : Array(String)
        @snapshot.try(&.profiles) || [] of String
      end

      def current_profile : String?
        @snapshot.try(&.current_profile)
      end

      def scene_collections : Array(String)
        @snapshot.try(&.scene_collections) || [] of String
      end

      def current_scene_collection : String?
        @snapshot.try(&.current_scene_collection)
      end

      def current_scene : String?
        @snapshot.try(&.current_scene)
      end

      def obs_connected? : Bool
        @snapshot.try(&.connected) || false
      end

      def streaming? : Bool
        @snapshot.try(&.output.streaming) || false
      end

      def recording? : Bool
        @snapshot.try(&.output.recording) || false
      end

      def stats : OBS::State::ObsStats?
        @snapshot.try(&.stats)
      end

      def stream_bitrate_kbps : Float64?
        @snapshot.try(&.stream_bitrate_kbps)
      end

      def stream_duration_ms : Int64?
        @snapshot.try(&.stream_duration_ms)
      end

      def record_duration_ms : Int64?
        @snapshot.try(&.record_duration_ms)
      end

      # Appends this frame's readings to the sparkline histories.
      #
      # Each series is sampled only when the snapshot actually carries it: a
      # snapshot with no stats must not push a zero, because a zero is a real
      # reading that would draw as a trough in the graph rather than as the
      # absence of data it really is.
      def record_metric_sample
        if current_stats = stats
          append_metric(@cpu_history, current_stats.cpu_usage_percent)
          append_metric(@fps_history, current_stats.active_fps)
        end
        if bitrate = stream_bitrate_kbps
          append_metric(@bitrate_history, bitrate)
        end
      end

      # Adds one reading and drops whatever has scrolled off the left edge.
      #
      # The trim lives here rather than in `record_metric_sample` so the bound
      # holds for every series by construction; it used to be a separate pass
      # over all three arrays afterwards, which is a rule that only holds as
      # long as someone remembers to add the next series to that list.
      private def append_metric(history : Array(Float64), value : Float64) : Nil
        history << value
        history.shift(history.size - METRIC_HISTORY_SAMPLES) if history.size > METRIC_HISTORY_SAMPLES
      end

      # Applies an optimistic volume value so rapid keyboard changes render
      # immediately while the debounced OBS command is still pending.
      def preview_audio_volume(input_name : String, percent : Int32) : Nil
        return unless @snapshot

        bounded = percent.clamp(0, 100)
        @pending_volumes[input_name] = bounded
        invalidate_audio_cache
      end

      # Forgets the optimistic value for one input, because the command that
      # carried it has finished and the daemon's own snapshots are now the
      # better answer.
      def settle_volume(input_name : String) : Nil
        return unless @pending_volumes.delete(input_name)

        invalidate_audio_cache
      end

      # The single place a snapshot is stored, so the pending-edit rule cannot
      # be skipped by a caller that assigns the field directly: an edit the
      # user is still making is newer than any snapshot the daemon computed
      # before that edit reached it, and therefore wins.
      # Adopts a new snapshot, keeping the scene cursors on the scenes they were
      # pointing at.
      #
      # The cursors are indexes into the visible scene list, and a snapshot can
      # change what that list contains -- a scene profile switched on here, by
      # the CLI, or by a second dashboard; a scene added or removed in OBS.
      # Clamping alone keeps an index in range but not on the same scene, so the
      # highlight would slide to a neighbour and the next Enter would tell OBS
      # to switch to whatever it landed on. Re-seeking by name is what stops a
      # filter change from becoming an unasked-for scene change.
      #
      # A cursor whose scene the new snapshot no longer shows has nowhere to go
      # and keeps the clamped position.
      def snapshot=(snapshot : OBS::State::ObsSnapshot?) : OBS::State::ObsSnapshot?
        focused = focused_scene.try(&.name)
        picked = scenes[@scene_picker_cursor]?.try(&.name)
        @snapshot = snapshot
        invalidate_snapshot_caches
        retarget_scene_cursors(focused, picked)
        @snapshot
      end

      private def with_pending_volumes(inputs : Array(OBS::State::AudioState)) : Array(OBS::State::AudioState)
        return inputs if @pending_volumes.empty?

        updated = inputs.dup
        changed = false
        updated.each_with_index do |input, index|
          percent = @pending_volumes[input.name]?
          next unless percent
          changed = true
          updated[index] = input.copy_with(
            volume_mul: Domain::Volume.percent_to_mul(percent),
            volume_percent: percent
          )
        end
        changed ? updated : inputs
      end

      private def invalidate_snapshot_caches : Nil
        @audio_inputs_cache = nil
        @scenes_cache = nil
        @scene_profiles_cache = nil
        @scene_picker_entries_cache = nil
        @scene_profile_list_entries_cache = nil
      end

      private def invalidate_audio_cache : Nil
        @audio_inputs_cache = nil
      end

      # Records a meter reading and raises the peak hold when the reading beats
      # whatever is left of the last one.
      def record_meter_level(input_name : String, level : Float64) : Nil
        @meter_levels[input_name] = level
        fraction = Meter.fraction(level)
        held = meter_peak(input_name)
        @meter_peaks[input_name] = {fraction, @anim.frame} if held.nil? || fraction >= held
      end

      # How far up the meter the peak marker has fallen to by now, or nil once
      # it has slid all the way back to the floor.
      def meter_peak(input_name : String) : Float64?
        peak = @meter_peaks[input_name]?
        return unless peak
        remaining = peak[0] - (@anim.frame - peak[1]).to_f64 * Meter::PEAK_FALL_PER_FRAME
        remaining > 0.0 ? remaining : nil
      end

      def push_log(entry : LogEntry)
        @logs << entry
        @logs.shift(@logs.size - MAX_LOG_ENTRIES) if @logs.size > MAX_LOG_ENTRIES
      end

      def set_last_result(message : String)
        @last_result = message
        @last_result_frame = @anim.frame
      end

      def revealed_last_result(characters_per_frame : Int32) : String?
        result = @last_result
        return unless result
        elapsed = (@anim.frame - @last_result_frame).to_i64
        result.each_grapheme.first(elapsed * characters_per_frame.clamp(1, Int32::MAX)).join
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

      # Cursor moves are clamped rather than wrapped: `G` on the last item and
      # a half page past the end both stop at the end, the way they do in vim.
      def move_to(index : Int32)
        set_cursor(@focus, index.clamp(0, {item_count - 1, 0}.max))
      end

      def cursor(panel : FocusPanel = @focus) : Int32
        @cursors[panel]
      end

      # Places a panel's cursor without moving focus, which is what a click
      # needs: the pointer says both which panel and which row.
      def set_cursor(panel : FocusPanel, index : Int32) : Nil
        @cursors[panel] = index
      end

      # The per-panel names the widgets and the hit test read.
      {% for panel, name in {Scenes: "scene", Audio: "audio", Profiles: "profile", Collections: "collection"} %}
        def {{ name.id }}_cursor : Int32
          cursor(FocusPanel::{{ panel.id }})
        end

        def {{ name.id }}_cursor=(index : Int32) : Nil
          set_cursor(FocusPanel::{{ panel.id }}, index)
        end
      {% end %}

      # Exhaustive `in` rather than `when`/`else`: a fifth panel then becomes a
      # compile error here instead of silently counting scene collections.
      def item_count(panel : FocusPanel = @focus) : Int32
        case panel
        in .scenes?      then scenes.size
        in .audio?       then audio_inputs.size
        in .profiles?    then profiles.size
        in .collections? then scene_collections.size
        end
      end

      # Pulls every cursor back inside its panel after the lists change, so a
      # scene deleted in OBS cannot leave a cursor pointing past the end.
      def clamp_cursors
        @cursors.each_key do |panel|
          @cursors[panel] = ListCursor.clamped(@cursors[panel], item_count(panel))
        end
        @scene_picker_cursor = ListCursor.clamped(@scene_picker_cursor, scenes.size)
        # Against `all_scenes`, not `scenes`: the editor is the one surface
        # that lists hidden scenes too, so clamping it to the visible list
        # would put its cursor out of reach of exactly the rows it exists to
        # unhide.
        @scene_profile_editor.clamp(all_scenes.size)
        # Against the row count, which is one more than the number of profiles:
        # the "show every scene" row is a row like any other here.
        @scene_profile_list.clamp(scene_profile_list_entries.size)
      end

      # Moves the scene picker's cursor. The picker keeps its cursor as a plain
      # property rather than in a state object of its own -- it has no sub-mode
      # to carry -- so this is where it reaches the shared rule.
      def move_scene_picker_cursor(delta : Int32) : Nil
        @scene_picker_cursor = ListCursor.moved(@scene_picker_cursor, delta, scenes.size)
      end

      # Re-seeks the two scene cursors onto the named scenes, and clamps
      # whatever is left over. `snapshot=` is the caller that matters; see the
      # reasoning there.
      def retarget_scene_cursors(scene_name : String?, picker_name : String?) : Nil
        clamp_cursors
        visible = scenes
        if scene_name && (index = visible.index { |scene| scene.name == scene_name })
          set_cursor(FocusPanel::Scenes, index)
        end
        if picker_name && (index = visible.index { |scene| scene.name == picker_name })
          @scene_picker_cursor = index
        end
      end

      def focused_scene : OBS::State::SceneState?
        scenes[scene_cursor]?
      end

      def focused_audio : OBS::State::AudioState?
        audio_inputs[audio_cursor]?
      end
    end
  end
end
