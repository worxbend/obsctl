require "../domain/command_parser"
require "./completion"
require "./input"
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

      def initialize(
        @model : Model,
        @sender : Sender,
        @theme_persister : ThemePersister? = nil,
        @volume_debounce : Time::Span = VOLUME_DEBOUNCE,
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

      def handle(action : Action) : ActionOutcome
        if move = FOCUS_ACTIONS[action.kind]?
          move.call(@model)
          return ActionOutcome.new
        end

        pointer_action(action) ||
          palette_action(action) ||
          navigation_action(action) ||
          settings_action(action) ||
          command_action(action) ||
          ActionOutcome.new
      end

      private def palette_action(action : Action) : ActionOutcome?
        case action.kind
        when .open_palette?
          palette = @model.command_palette
          palette.active = true
          palette.input = "/"
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
        when .complete_next?
          @model.command_palette.cycle_next
          ActionOutcome.new
        when .complete_previous?
          @model.command_palette.cycle_previous
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
        when .volume_down? then volume(-5)
        when .volume_up?   then volume(5)
        end
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
        when .apply_settings_theme?
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
        when .reload_config?  then command(IPC::CommandPayload.new("reload_config"))
        when .dump_config?    then command(IPC::CommandPayload.new("dump_config"))
        when .retry_connect?  then ActionOutcome.new(retry_subscription: true, message: "Reconnected to daemon.")
        when .activate_scene? then target_command("set_scene", @model.focused_scene.try(&.name))
        when .activate_profile?
          target_command("set_profile", @model.profiles[@model.profile_cursor]?)
        when .activate_collection?
          target_command("set_scene_collection", @model.scene_collections[@model.collection_cursor]?)
        when .toggle_mute?
          target_command("toggle_mute", @model.focused_audio.try(&.name))
        end
      end

      private def dispatch_palette(input : String) : ActionOutcome
        normalized = input.strip.downcase
        return ActionOutcome.new(quit: true) if normalized == "/quit" || normalized == "/exit"
        if SETTINGS_ALIASES.includes?(normalized)
          return handle(Action.new(ActionKind::OpenSettings))
        end
        if normalized == "/help"
          return ActionOutcome.new(message: palette_help)
        end
        parsed = Domain::CommandParser.new.parse(input)
        command(payload_for(parsed))
      rescue ex : Domain::ObsctlError
        ActionOutcome.new(message: "error: #{ex.message}")
      end

      # `/themes` is a dashboard-only view, so it has no registry entry and is
      # appended to the generated list.
      SETTINGS_ALIASES = ["/themes", "/theme", "/settings"]

      private def palette_help : String
        usages = Domain::CommandRegistry
          .for_surface(Domain::CommandSurface::Palette)
          .map { |spec| "/#{spec.usage}" }
        "Commands: #{(usages << SETTINGS_ALIASES.first).join(' ')}"
      end

      # Where the dashboard deliberately asks for something other than the
      # command's default IPC name.
      #
      # `/status` in the palette should refresh the panels rather than print a
      # report, and `/connect` is a request to re-establish the OBS link.
      TUI_PAYLOAD_OVERRIDES = {
        Domain::StatusCommand  => "get_snapshot",
        Domain::ConnectCommand => "reconnect_obs",
      }

      private def payload_for(command : Domain::Command) : IPC::CommandPayload
        {% for type, name in TUI_PAYLOAD_OVERRIDES %}
          return IPC::CommandPayload.new({{ name }}) if command.is_a?({{ type }})
        {% end %}

        name = command.ipc_name
        raise Domain::CommandParseError.new("unsupported TUI command") unless name

        IPC::CommandPayload.new(name, command.target, command.percent)
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

          response = @sender.call(IPC::CommandPayload.new("set_volume", input_name, percent))
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
