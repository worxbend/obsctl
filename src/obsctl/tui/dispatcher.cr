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
      alias Sender = Proc(IPC::CommandPayload, IPC::Response)
      alias ThemePersister = Proc(Theme, String)

      def initialize(@model : Model, @sender : Sender, @theme_persister : ThemePersister? = nil)
      end

      def handle(action : Action) : ActionOutcome
        case action.kind
        when .quit?
          ActionOutcome.new(quit: true)
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
          @model.command_palette.input = @model.command_palette.input.each_grapheme.to_a[0...-1].join unless @model.command_palette.input.empty?
          refresh_completions
          ActionOutcome.new
        when .palette_submit?
          input = @model.command_palette.input
          close_palette
          dispatch_palette(input)
        when .reload_config?
          command(IPC::CommandPayload.new("reload_config"))
        when .dump_config?
          command(IPC::CommandPayload.new("dump_config"))
        when .retry_connect?
          ActionOutcome.new(retry_subscription: true, message: "Reconnected to daemon.")
        when .focus_scenes?
          @model.focus = FocusPanel::Scenes; ActionOutcome.new
        when .focus_audio?
          @model.focus = FocusPanel::Audio; ActionOutcome.new
        when .focus_profiles?
          @model.focus = FocusPanel::Profiles; ActionOutcome.new
        when .focus_collections?
          @model.focus = FocusPanel::Collections; ActionOutcome.new
        when .focus_pane_left?
          @model.focus = @model.focus.left; ActionOutcome.new
        when .focus_pane_right?
          @model.focus = @model.focus.right; ActionOutcome.new
        when .focus_pane_up?
          @model.focus = @model.focus.up; ActionOutcome.new
        when .focus_pane_down?
          @model.focus = @model.focus.down; ActionOutcome.new
        when .navigate_up?
          @model.move_up; ActionOutcome.new
        when .navigate_down?
          @model.move_down; ActionOutcome.new
        when .activate_scene?
          target_command("set_scene", @model.focused_scene.try(&.name))
        when .activate_profile?
          target_command("set_profile", @model.profiles[@model.profile_cursor]?)
        when .activate_collection?
          target_command("set_scene_collection", @model.scene_collections[@model.collection_cursor]?)
        when .toggle_mute?
          target_command("toggle_mute", @model.focused_audio.try(&.name))
        when .volume_down?
          volume(-5)
        when .volume_up?
          volume(5)
        when .complete_next?
          @model.command_palette.cycle_next; ActionOutcome.new
        when .complete_previous?
          @model.command_palette.cycle_previous; ActionOutcome.new
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
          message = @theme_persister.try(&.call(@model.theme)) || "theme set: #{@model.theme.id}"
          ActionOutcome.new(message: message)
        else
          ActionOutcome.new
        end
      end

      private def dispatch_palette(input : String) : ActionOutcome
        normalized = input.strip.downcase
        return ActionOutcome.new(quit: true) if normalized == "/quit" || normalized == "/exit"
        if {"/themes", "/theme", "/settings"}.includes?(normalized)
          return handle(Action.new(ActionKind::OpenSettings))
        end
        if normalized == "/help"
          return ActionOutcome.new(message: "Commands: /scene /profile /collection /mute /unmute /toggle-mute /vol /stream /rec /status /obs-status /server-status /reload-config /dump-config /validate-config /themes /reconnect /quit")
        end
        parsed = Domain::CommandParser.new.parse(input)
        command(payload_for(parsed))
      rescue ex : Domain::ObsctlError
        ActionOutcome.new(message: "error: #{ex.message}")
      end

      private def payload_for(command : Domain::Command) : IPC::CommandPayload
        case command
        when Domain::StatusCommand         then IPC::CommandPayload.new("get_snapshot")
        when Domain::ObsStatusCommand      then IPC::CommandPayload.new("get_obs_status")
        when Domain::ServerStatusCommand   then IPC::CommandPayload.new("get_server_status")
        when Domain::ValidateConfigCommand then IPC::CommandPayload.new("validate_config")
        when Domain::ReconnectCommand, Domain::ConnectCommand
          IPC::CommandPayload.new("reconnect_obs")
        when Domain::ShutdownServerCommand     then IPC::CommandPayload.new("shutdown_server")
        when Domain::DumpConfigCommand         then IPC::CommandPayload.new("dump_config")
        when Domain::ReloadConfigCommand       then IPC::CommandPayload.new("reload_config")
        when Domain::SetSceneCommand           then IPC::CommandPayload.new("set_scene", command.target)
        when Domain::SetProfileCommand         then IPC::CommandPayload.new("set_profile", command.target)
        when Domain::SetSceneCollectionCommand then IPC::CommandPayload.new("set_scene_collection", command.target)
        when Domain::MuteCommand               then IPC::CommandPayload.new("mute", command.target)
        when Domain::UnmuteCommand             then IPC::CommandPayload.new("unmute", command.target)
        when Domain::ToggleMuteCommand         then IPC::CommandPayload.new("toggle_mute", command.target)
        when Domain::VolumeCommand             then IPC::CommandPayload.new("set_volume", command.target, command.percent)
        when Domain::ToggleStreamCommand       then IPC::CommandPayload.new("toggle_stream")
        when Domain::ToggleRecordCommand       then IPC::CommandPayload.new("toggle_record")
        else                                        raise Domain::CommandParseError.new("unsupported TUI command")
        end
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
        command(IPC::CommandPayload.new("set_volume", input.name, percent))
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
