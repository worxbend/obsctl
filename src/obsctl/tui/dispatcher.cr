require "../domain/command_parser"
require "../ipc/command_name"
require "./completion"
require "./input"
require "./layout"
require "./session"

module Obsctl
  module TUI
    record ActionOutcome,
      quit : Bool = false,
      retry_subscription : Bool = false,
      message : String? = nil

    class Dispatcher
      VOLUME_DEBOUNCE = 120.milliseconds

      alias Sender = Proc(IPC::CommandPayload, IPC::Response)
      alias ThemePersister = Proc(Theme, String)
      alias Viewport = Proc(CryTUI::Rect)

      # Half-page steps need to know how tall the focused panel is. The area is
      # read through a proc rather than stored because it changes with every
      # resize, and asking at the moment of the keypress is what keeps the step
      # matched to what is on screen.
      DEFAULT_PAGE_STEP = 5

      def initialize(
        @model : Model,
        @sender : Sender,
        @theme_persister : ThemePersister? = nil,
        @volume_debounce : Time::Span = VOLUME_DEBOUNCE,
        @viewport : Viewport? = nil,
      )
        @volume_versions = Hash(String, UInt64).new(0_u64)
      end

      # Actions that only move focus or the cursor, with no daemon round trip.
      FOCUS_ACTIONS = {
        ActionKind::FocusScenes      => ->(model : Model) { model.focus = FocusPanel::Scenes },
        ActionKind::FocusAudio       => ->(model : Model) { model.focus = FocusPanel::Audio },
        ActionKind::FocusProfiles    => ->(model : Model) { model.focus = FocusPanel::Profiles },
        ActionKind::FocusCollections => ->(model : Model) { model.focus = FocusPanel::Collections },
        ActionKind::FocusPaneLeft    => ->(model : Model) { model.focus = model.focus.left },
        ActionKind::FocusPaneRight   => ->(model : Model) { model.focus = model.focus.right },
        ActionKind::FocusPaneUp      => ->(model : Model) { model.focus = model.focus.up },
        ActionKind::FocusPaneDown    => ->(model : Model) { model.focus = model.focus.down },
      }

      # Every action ends the sequence that produced it; only a fresh prefix
      # leaves one pending. Clearing here rather than in each branch is what
      # guarantees the which-key menu closes on whatever the next key does.
      def handle(action : Action) : ActionOutcome
        outcome = dispatch(action)
        @model.pending_sequence = action.kind.pending_sequence? ? (action.sequence || "") : ""
        outcome
      end

      private def dispatch(action : Action) : ActionOutcome
        return ActionOutcome.new if action.kind.pending_sequence? || action.kind.clear_sequence?

        if move = FOCUS_ACTIONS[action.kind]?
          move.call(@model)
          return ActionOutcome.new
        end

        pointer_action(action) ||
          palette_action(action) ||
          scene_picker_action(action) ||
          navigation_action(action) ||
          settings_action(action) ||
          command_action(action) ||
          ActionOutcome.new
      end

      private def scene_picker_action(action : Action) : ActionOutcome?
        case action.kind
        when .open_scene_picker?
          # Refusing to open on an empty list rather than showing an empty box:
          # the picker swallows every key while it is open, so a picker with
          # nothing to pick would be a dead end with no visible reason.
          return ActionOutcome.new(message: "no scenes to switch to") if @model.scenes.empty?

          # Opens on the scene that is live, so the cursor starts where the eye
          # already is instead of at the top of the list.
          @model.scene_picker_cursor = @model.scenes.index(&.active) || 0
          @model.scene_picker_active = true
          ActionOutcome.new
        when .close_scene_picker?
          @model.scene_picker_active = false
          ActionOutcome.new
        when .scene_picker_navigate_up?
          @model.scene_picker_cursor = {@model.scene_picker_cursor - 1, 0}.max
          ActionOutcome.new
        when .scene_picker_navigate_down?
          @model.scene_picker_cursor = {@model.scene_picker_cursor + 1, {@model.scenes.size - 1, 0}.max}.min
          ActionOutcome.new
        when .scene_picker_activate?
          switch_scene(@model.scene_picker_cursor)
        when .pick_scene?
          index = action.index
          index ? switch_scene(index) : ActionOutcome.new
        end
      end

      # Closes the picker and sends the switch.
      #
      # The dashboard's own scene cursor is moved to match, so the panel
      # underneath agrees with what was just picked and a later Enter on the
      # scenes panel repeats the same switch rather than a stale one.
      private def switch_scene(index : Int32) : ActionOutcome
        @model.scene_picker_active = false
        scene = @model.scenes[index]?
        return ActionOutcome.new unless scene

        @model.scene_cursor = index
        target_command(IPC::CommandName::SET_SCENE, scene.name)
      end

      private def palette_action(action : Action) : ActionOutcome?
        case action.kind
        when .open_palette?
          palette = @model.command_palette
          palette.active = true
          palette.input = (action.character || @model.command_palette_prefix[0]? || '/').to_s
          refresh_completions
          ActionOutcome.new
        when .close_palette?
          close_palette
          ActionOutcome.new
        when .palette_character?
          @model.command_palette.input += action.character.to_s
          refresh_completions
          ActionOutcome.new
        when .palette_backspace?
          unless @model.command_palette.input.empty?
            @model.command_palette.input = @model.command_palette.input.each_grapheme.to_a[0...-1].join
          end
          refresh_completions
          ActionOutcome.new
        when .palette_submit?
          input = @model.command_palette.input
          close_palette
          dispatch_palette(input)
        when .palette_clear_line?
          # `Ctrl-U` clears the arguments but keeps the leader, so the line is
          # ready to retype rather than closed.
          palette = @model.command_palette
          palette.input = palette.input.each_grapheme.first(1).join
          refresh_completions
          ActionOutcome.new
        when .palette_delete_word?
          palette = @model.command_palette
          palette.input = palette.input.rstrip.sub(/[^\s]*$/, "")
          refresh_completions
          ActionOutcome.new
        when .complete_next?
          @model.command_palette.cycle_next
          ActionOutcome.new
        when .complete_previous?
          @model.command_palette.cycle_previous
          ActionOutcome.new
        when .pointer_completion?
          index = action.index
          completion = index ? @model.command_palette.completions[index]? : nil
          if completion
            @model.command_palette.input = completion
            @model.command_palette.completion_index = index
          end
          ActionOutcome.new
        end
      end

      private def navigation_action(action : Action) : ActionOutcome?
        case action.kind
        when .navigate_up?
          @model.move_up
          ActionOutcome.new
        when .navigate_down?
          @model.move_down
          ActionOutcome.new
        when .navigate_top?
          @model.move_top
          ActionOutcome.new
        when .navigate_bottom?
          @model.move_bottom
          ActionOutcome.new
        when .navigate_half_page_up?
          @model.move_by(-page_step)
          ActionOutcome.new
        when .navigate_half_page_down?
          @model.move_by(page_step)
          ActionOutcome.new
        when .volume_down? then volume(-5)
        when .volume_up?   then volume(5)
        end
      end

      # Half of the focused panel's visible rows, the way vim measures
      # `Ctrl-D`. Without a viewport -- before the first frame, or in a spec
      # that renders nothing -- a fixed step keeps the key useful.
      private def page_step : Int32
        area = @viewport.try(&.call)
        return DEFAULT_PAGE_STEP if area.nil? || area.empty?

        rows = DashboardLayout.compute(area, @model.streaming?).panel(@model.focus).height - 2
        {rows // 2, 1}.max
      end

      private def settings_action(action : Action) : ActionOutcome?
        case action.kind
        when .open_settings?
          @model.theme_preview_origin = @model.theme
          @model.settings_cursor = Theme::ALL.index(@model.theme) || 0
          @model.view = View::Settings
          ActionOutcome.new
        when .close_settings?
          @model.theme = @model.theme_preview_origin || @model.theme
          @model.theme_preview_origin = nil
          @model.view = View::Main
          ActionOutcome.new
        when .settings_navigate_up?
          @model.settings_cursor = {@model.settings_cursor - 1, 0}.max
          @model.theme = Theme::ALL[@model.settings_cursor]
          ActionOutcome.new
        when .settings_navigate_down?
          @model.settings_cursor = {@model.settings_cursor + 1, Theme::ALL.size - 1}.min
          @model.theme = Theme::ALL[@model.settings_cursor]
          ActionOutcome.new
        when .pointer_settings_select?
          index = action.index
          if index && (theme = Theme::ALL[index]?)
            @model.settings_cursor = index
            @model.theme = theme
          end
          ActionOutcome.new
        when .apply_settings_theme?, .pointer_settings_apply?
          @model.theme_preview_origin = nil
          @model.view = View::Main
          ActionOutcome.new(message: @theme_persister.try(&.call(@model.theme)) || "theme set: #{@model.theme.id}")
        end
      end

      POINTER_KINDS = [
        ActionKind::PointerFocus,
        ActionKind::PointerActivate,
        ActionKind::PointerToggleMute,
        ActionKind::PointerVolumeUp,
        ActionKind::PointerVolumeDown,
      ]

      # Pointer actions carry the panel and row they were resolved against, so
      # they place focus and the cursor themselves before doing anything. The
      # keyboard equivalents read whatever is focused; these must not, or a
      # click would act on the panel the keyboard happened to leave selected.
      private def pointer_action(action : Action) : ActionOutcome?
        panel = action.panel
        return unless panel
        return unless POINTER_KINDS.includes?(action.kind)

        @model.focus = panel
        if index = action.index
          case panel
          when .scenes?      then @model.scene_cursor = index
          when .audio?       then @model.audio_cursor = index
          when .profiles?    then @model.profile_cursor = index
          when .collections? then @model.collection_cursor = index
          end
          @model.clamp_cursors
        end

        case action.kind
        when .pointer_activate?
          case panel
          when .scenes?      then command_action(Action.new(ActionKind::ActivateScene))
          when .profiles?    then command_action(Action.new(ActionKind::ActivateProfile))
          when .collections? then command_action(Action.new(ActionKind::ActivateCollection))
          when .audio?       then command_action(Action.new(ActionKind::ToggleMute))
          else                    ActionOutcome.new
          end
        when .pointer_toggle_mute?
          command_action(Action.new(ActionKind::ToggleMute))
        when .pointer_volume_up?
          # Through the ordinary volume path, so a spun wheel gets the same
          # optimistic redraw and debounced OBS command a held arrow key does.
          navigation_action(Action.new(ActionKind::VolumeUp))
        when .pointer_volume_down?
          navigation_action(Action.new(ActionKind::VolumeDown))
        else
          ActionOutcome.new
        end
      end

      private def command_action(action : Action) : ActionOutcome?
        case action.kind
        when .quit?           then ActionOutcome.new(quit: true)
        when .reload_config?  then command(IPC::CommandPayload.new(IPC::CommandName::RELOAD_CONFIG))
        when .dump_config?    then command(IPC::CommandPayload.new(IPC::CommandName::DUMP_CONFIG))
        when .retry_connect?  then ActionOutcome.new(retry_subscription: true, message: "Reconnected to daemon.")
        when .activate_scene? then target_command(IPC::CommandName::SET_SCENE, @model.focused_scene.try(&.name))
        when .activate_profile?
          target_command(IPC::CommandName::SET_PROFILE, @model.profiles[@model.profile_cursor]?)
        when .activate_collection?
          target_command(IPC::CommandName::SET_SCENE_COLLECTION, @model.scene_collections[@model.collection_cursor]?)
        when .toggle_mute?
          target_command(IPC::CommandName::TOGGLE_MUTE, @model.focused_audio.try(&.name))
        end
      end

      # The palette accepts either leader, so the line is read without one and
      # the vim spellings of quit and help are answered before the registry is
      # consulted.
      PALETTE_LEADERS = "/:"
      QUIT_WORDS      = ["q", "q!", "qa", "qa!", "quit", "quit!", "exit", "x", "wq"]
      HELP_WORDS      = ["h", "help"]

      private def dispatch_palette(input : String) : ActionOutcome
        line = input.strip.lstrip(PALETTE_LEADERS)
        normalized = line.strip.downcase
        return ActionOutcome.new(quit: true) if QUIT_WORDS.includes?(normalized)
        if SETTINGS_ALIASES.includes?(normalized)
          return handle(Action.new(ActionKind::OpenSettings))
        end
        if HELP_WORDS.includes?(normalized)
          return ActionOutcome.new(message: palette_help)
        end
        parsed = Domain::CommandParser.new.parse(line)
        command(payload_for(parsed))
      rescue ex : Domain::ObsctlError
        ActionOutcome.new(message: "error: #{ex.message}")
      end

      # `themes` is a dashboard-only view, so it has no registry entry and is
      # appended to the generated list.
      SETTINGS_ALIASES = ["themes", "theme", "settings"]

      private def palette_help : String
        usages = Domain::CommandRegistry
          .for_surface(Domain::CommandSurface::Palette)
          .map { |spec| "/#{spec.usage}" }
        "Commands: #{(usages << "/#{SETTINGS_ALIASES.first}").join(' ')}"
      end

      # Where the dashboard deliberately asks for something other than the
      # command's default IPC name.
      #
      # `/status` in the palette should refresh the panels rather than print a
      # report, and `/connect` is a request to re-establish the OBS link.
      TUI_PAYLOAD_OVERRIDES = {
        Domain::StatusCommand  => IPC::CommandName::GET_SNAPSHOT,
        Domain::ConnectCommand => IPC::CommandName::RECONNECT_OBS,
      }

      private def payload_for(command : Domain::Command) : IPC::CommandPayload
        {% for type, name in TUI_PAYLOAD_OVERRIDES %}
          return IPC::CommandPayload.new({{ name }}) if command.is_a?({{ type }})
        {% end %}

        command.to_payload
      end

      private def command(payload : IPC::CommandPayload) : ActionOutcome
        response = @sender.call(payload)
        message = if response.ok
                    response.result.try(&.["message"]?).try(&.as_s?) || "ok"
                  elsif error = response.error
                    "error [#{error.code}]: #{error.message}"
                  else
                    "error: invalid server response"
                  end
        ActionOutcome.new(message: message)
      rescue ex : Domain::ObsctlError | IO::Error
        ActionOutcome.new(message: "error: #{ex.message}")
      end

      private def target_command(name : String, target : String?) : ActionOutcome
        return ActionOutcome.new unless target
        command(IPC::CommandPayload.new(name, target))
      end

      private def volume(delta : Int32) : ActionOutcome
        input = @model.focused_audio
        return ActionOutcome.new unless input
        percent = ((input.volume_percent || 50) + delta).clamp(0, 100)
        @model.preview_audio_volume(input.name, percent)
        debounce_volume(input.name, percent)
        ActionOutcome.new
      end

      private def debounce_volume(input_name : String, percent : Int32) : Nil
        version = @volume_versions[input_name] &+ 1
        @volume_versions[input_name] = version
        spawn(name: "obsctl-volume-debounce") do
          sleep @volume_debounce
          next unless @volume_versions[input_name] == version

          response = @sender.call(IPC::CommandPayload.new(IPC::CommandName::SET_VOLUME, input_name, percent))
          unless response.ok
            error = response.error
            @model.set_last_result(error ? "error [#{error.code}]: #{error.message}" : "error: invalid server response")
          end
        rescue ex : Domain::ObsctlError | IO::Error
          @model.set_last_result("error: #{ex.message}")
        end
      end

      private def refresh_completions
        palette = @model.command_palette
        palette.completions = Completion.compute(palette.input, @model)
        palette.completion_index = nil
      end

      private def close_palette
        palette = @model.command_palette
        palette.active = false
        palette.input = ""
        palette.completions.clear
        palette.completion_index = nil
      end
    end
  end
end
