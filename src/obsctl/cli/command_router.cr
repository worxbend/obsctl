require "../config/config"
require "../config/config_loader"
require "../config/config_schema"
require "../config/config_writer"
require "../config/config_dump"
require "../domain/aliases"
require "../domain/command"
require "../domain/command_result"
require "../obs/client"

module Obsctl
  module CLI
    class CommandRouter
      def initialize(@config : Config::Config, @config_path : String)
      end

      def execute(command : Domain::Command) : Domain::CommandResult
        case command
        when Domain::HelpCommand
          Domain::CommandResult.ok(help_text)
        when Domain::StatusCommand
          with_client do |client|
            snapshot = client.snapshot
            lines = [] of String
            lines << "connected: true"
            lines << "current_scene: #{snapshot.current_scene || "-"}"
            lines << "scenes:"
            snapshot.scenes.each { |scene| lines << "  #{scene.active ? "*" : "-"} #{scene.name}" }
            lines << "audio:"
            snapshot.audio_inputs.each do |input|
              muted = input.muted.nil? ? "unknown" : (input.muted ? "muted" : "live")
              volume = input.volume_percent ? "#{input.volume_percent}%" : "unknown"
              lines << "  - #{input.name} #{muted} volume=#{volume}"
            end
            Domain::CommandResult.ok(lines.join('\n'))
          end
        when Domain::SetSceneCommand
          scene = Domain::Aliases.resolve_scene(@config, command.target)
          with_client { |client| client.set_scene(scene.name) }
          Domain::CommandResult.ok("scene set: #{scene.name}")
        when Domain::MuteCommand
          input = Domain::Aliases.resolve_audio(@config, command.target)
          with_client { |client| client.mute(input.name, true) }
          Domain::CommandResult.ok("muted: #{input.name}")
        when Domain::UnmuteCommand
          input = Domain::Aliases.resolve_audio(@config, command.target)
          with_client { |client| client.mute(input.name, false) }
          Domain::CommandResult.ok("unmuted: #{input.name}")
        when Domain::ToggleMuteCommand
          input = Domain::Aliases.resolve_audio(@config, command.target)
          with_client { |client| client.toggle_mute(input.name) }
          Domain::CommandResult.ok("toggled mute: #{input.name}")
        when Domain::VolumeCommand
          input = Domain::Aliases.resolve_audio(@config, command.target)
          with_client { |client| client.set_volume(input.name, command.percent) }
          Domain::CommandResult.ok("volume set: #{input.name} #{command.percent}%")
        when Domain::DumpConfigCommand
          with_client do |client|
            merged = Config::ConfigDump.merge(@config, client.scene_names, client.input_names)
            Config::ConfigWriter.new.write(@config_path, merged, backup: true)
            Domain::CommandResult.ok("config dumped: #{@config_path}")
          end
        when Domain::ValidateConfigCommand
          Config::ConfigSchema.validate!(@config)
          Domain::CommandResult.ok("config valid: #{@config_path}")
        when Domain::ReloadConfigCommand
          Domain::CommandResult.ok("config reload is handled by the caller")
        when Domain::ReconnectCommand
          Domain::CommandResult.ok("reconnect is handled by the server")
        when Domain::ConnectCommand
          with_client { }
          Domain::CommandResult.ok("connected")
        when Domain::DisconnectCommand
          Domain::CommandResult.ok("disconnected")
        when Domain::QuitCommand
          Domain::CommandResult.ok("quit")
        else
          Domain::CommandResult.failed("unsupported command")
        end
      end

      private def with_client(&)
        client = OBS::Client.new(@config)
        client.connect
        result = yield client
        client.close
        result
      rescue ex
        client.try(&.close)
        raise ex
      end

      private def help_text : String
        "/help /set-scene <target> /scene <target> /mute <target> /unmute <target> /toggle-mute <target> /vol <target> <0-100> /status /server-status /obs-status /reconnect /validate-config /dump-config /reload-config /connect /disconnect /quit"
      end
    end
  end
end
