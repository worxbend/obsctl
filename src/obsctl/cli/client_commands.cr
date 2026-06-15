require "json"
require "../domain/command"
require "../domain/command_result"
require "../domain/errors"
require "../ipc/protocol"

module Obsctl
  module CLI
    class ClientCommands
      def initialize(@client : IPC::UnixClient = IPC::UnixClient.new)
        @sequence = 0
      end

      def execute(command : Domain::Command) : Domain::CommandResult
        response = @client.request(request_for(command))
        unless response.ok
          error = response.error
          raise_remote_error(error.not_nil!) if error
          raise Domain::IpcProtocolError.new("server returned an invalid error response")
        end

        Domain::CommandResult.ok(format_response(command, response.result))
      rescue ex : Domain::IpcConnectionFailed
        raise Domain::ServerUnavailable.new
      end

      private def request_for(command : Domain::Command) : IPC::Request
        IPC::Request.new(next_id, IPC::Request::TYPE_COMMAND, payload_for(command))
      end

      private def payload_for(command : Domain::Command) : IPC::CommandPayload
        case command
        when Domain::StatusCommand
          IPC::CommandPayload.new("get_obs_status")
        when Domain::ServerStatusCommand
          IPC::CommandPayload.new("get_server_status")
        when Domain::SetSceneCommand
          IPC::CommandPayload.new("set_scene", command.target)
        when Domain::MuteCommand
          IPC::CommandPayload.new("mute", command.target)
        when Domain::UnmuteCommand
          IPC::CommandPayload.new("unmute", command.target)
        when Domain::ToggleMuteCommand
          IPC::CommandPayload.new("toggle_mute", command.target)
        when Domain::VolumeCommand
          IPC::CommandPayload.new("set_volume", command.target, command.percent)
        when Domain::DumpConfigCommand
          IPC::CommandPayload.new("dump_config")
        when Domain::ReloadConfigCommand
          IPC::CommandPayload.new("reload_config")
        else
          raise Domain::CommandParseError.new("unsupported CLI command")
        end
      end

      private def format_response(command : Domain::Command, result : JSON::Any?) : String
        return "ok" unless result

        case command
        when Domain::StatusCommand
          format_obs_status(result)
        when Domain::ServerStatusCommand
          format_server_status(result)
        else
          result["message"]?.try(&.as_s?) || "ok"
        end
      end

      private def format_obs_status(result : JSON::Any) : String
        lines = [] of String
        connected = result["connected"]?.try(&.as_bool?) || false
        lines << "connected: #{connected}"
        lines << "current_scene: #{result["current_scene"]?.try(&.as_s?) || "-"}"
        lines << "scenes:"
        result["scenes"]?.try(&.as_a?).try do |scenes|
          scenes.each do |scene|
            active = scene["active"]?.try(&.as_bool?) || false
            lines << "  #{active ? "*" : "-"} #{scene["name"].as_s}"
          end
        end
        lines << "audio:"
        result["audio_inputs"]?.try(&.as_a?).try do |inputs|
          inputs.each do |input|
            muted = input["muted"]?.try(&.as_bool?)
            mute_text = muted.nil? ? "unknown" : (muted ? "muted" : "live")
            volume = input["volume_percent"]?.try(&.as_i?).try { |value| "#{value}%" } || "unknown"
            lines << "  - #{input["name"].as_s} #{mute_text} volume=#{volume}"
          end
        end
        lines.join('\n')
      end

      private def format_server_status(result : JSON::Any) : String
        lines = [] of String
        lines << "pid: #{result["pid"]?.try(&.as_i?) || "-"}"
        lines << "obs_connected: #{result["obs_connected"]?.try(&.as_bool?) || false}"
        lines << "last_error: #{result["last_error"]?.try(&.as_s?) || "-"}"
        lines.join('\n')
      end

      private def raise_remote_error(error : IPC::ErrorPayload) : NoReturn
        case error.code
        when "COMMAND_PARSE_ERROR"
          raise Domain::CommandParseError.new(error.message)
        when "CONFIG_ERROR"
          raise Domain::ConfigInvalid.new(error.message)
        when "OBS_UNAVAILABLE"
          raise Domain::ObsUnavailable.new(error.message)
        when "SCENE_NOT_FOUND", "AUDIO_INPUT_NOT_FOUND", "ALIAS_AMBIGUOUS", "REQUEST_FAILED"
          raise Domain::RemoteCommandFailed.new(error.message, Domain::ExitCode::ObsRequest)
        else
          raise Domain::RemoteCommandFailed.new(error.message, Domain::ExitCode::Failure)
        end
      end

      private def next_id : String
        @sequence += 1
        "req-%06d" % @sequence
      end
    end
  end
end
