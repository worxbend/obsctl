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

      def self.exit_code_for(error : IPC::ErrorPayload) : Domain::ExitCode
        case error.code
        when IPC::ErrorCode::SERVER_UNAVAILABLE, IPC::ErrorCode::OBS_UNAVAILABLE, IPC::ErrorCode::REQUEST_TIMEOUT
          Domain::ExitCode::Connection
        when IPC::ErrorCode::COMMAND_PARSE_ERROR, IPC::ErrorCode::SHUTDOWN_DISABLED, IPC::ErrorCode::ALIAS_AMBIGUOUS
          Domain::ExitCode::CommandParse
        when IPC::ErrorCode::CONFIG_INVALID
          Domain::ExitCode::Config
        when IPC::ErrorCode::SCENE_NOT_FOUND, IPC::ErrorCode::AUDIO_INPUT_NOT_FOUND, IPC::ErrorCode::OBS_REQUEST_FAILED
          Domain::ExitCode::ObsRequest
        when IPC::ErrorCode::IPC_PROTOCOL_ERROR
          Domain::ExitCode::Ipc
        else
          Domain::ExitCode::Failure
        end
      end

      def request(command : Domain::Command) : IPC::Response
        response = @client.request(request_for(command))
        if !response.ok && response.error.nil?
          raise Domain::IpcProtocolError.new("server returned an invalid error response")
        end
        response
      rescue ex : Domain::IpcConnectionFailed
        raise Domain::ServerUnavailable.new
      end

      def execute(command : Domain::Command) : Domain::CommandResult
        response = request(command)
        unless response.ok
          error = response.error
          raise_remote_error(error.not_nil!) if error
          raise Domain::IpcProtocolError.new("server returned an invalid error response")
        end

        Domain::CommandResult.ok(format_response(command, response.result))
      end

      private def request_for(command : Domain::Command) : IPC::Request
        IPC::Request.new(next_id, IPC::Request::TYPE_COMMAND, payload_for(command))
      end

      private def payload_for(command : Domain::Command) : IPC::CommandPayload
        case command
        when Domain::StatusCommand
          IPC::CommandPayload.new("status")
        when Domain::ObsStatusCommand
          IPC::CommandPayload.new("get_obs_status")
        when Domain::ServerStatusCommand
          IPC::CommandPayload.new("get_server_status")
        when Domain::ValidateConfigCommand
          IPC::CommandPayload.new("validate_config")
        when Domain::ReconnectCommand
          IPC::CommandPayload.new("reconnect_obs")
        when Domain::ShutdownServerCommand
          IPC::CommandPayload.new("shutdown_server")
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
          format_combined_status(result)
        when Domain::ObsStatusCommand
          format_obs_status(result)
        when Domain::ServerStatusCommand
          format_server_status(result)
        else
          result["message"]?.try(&.as_s?) || "ok"
        end
      end

      private def format_combined_status(result : JSON::Any) : String
        server = result["server"]?
        obs = result["obs"]?
        return format_obs_status(result) unless server && obs

        [
          "server:",
          indent(format_server_status(server)),
          "obs:",
          indent(format_obs_status(obs)),
        ].join('\n')
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

      private def indent(text : String) : String
        text.lines.map { |line| "  #{line}" }.join('\n')
      end

      private def format_server_status(result : JSON::Any) : String
        lines = [] of String
        lines << "pid: #{result["pid"]?.try(&.as_i?) || "-"}"
        lines << "uptime_seconds: #{result["uptime_seconds"]?.try(&.as_i?) || "-"}"
        lines << "socket_path: #{result["socket_path"]?.try(&.as_s?) || "-"}"
        lines << "client_count: #{result["client_count"]?.try(&.as_i?) || 0}"
        lines << "dropped_reconnect_diagnostic_logs: #{integer_text(result["dropped_reconnect_diagnostic_logs"]?)}"
        lines << "obs_connected: #{result["obs_connected"]?.try(&.as_bool?) || false}"
        lines << "reconnecting: #{result["reconnecting"]?.try(&.as_bool?) || false}"
        lines << "last_connected_at: #{timestamp_text(result["last_connected_at"]?)}"
        lines << "last_disconnected_at: #{timestamp_text(result["last_disconnected_at"]?)}"
        lines << "last_reconnect_attempt_at: #{timestamp_text(result["last_reconnect_attempt_at"]?)}"
        lines << "last_connection_failed_at: #{timestamp_text(result["last_connection_failed_at"]?)}"
        lines << "last_error: #{result["last_error"]?.try(&.as_s?) || "-"}"
        lines.join('\n')
      end

      private def timestamp_text(value : JSON::Any?) : String
        value.try(&.as_s?) || "-"
      end

      private def integer_text(value : JSON::Any?) : String
        value.try(&.as_i64?).try(&.to_s) || "0"
      end

      private def raise_remote_error(error : IPC::ErrorPayload) : NoReturn
        case code = self.class.exit_code_for(error)
        when Domain::ExitCode::Connection
          if error.code == IPC::ErrorCode::SERVER_UNAVAILABLE
            raise Domain::ServerUnavailable.new(error.message)
          end
          if error.code == IPC::ErrorCode::OBS_UNAVAILABLE
            raise Domain::ObsUnavailable.new(error.message)
          end
          raise Domain::RemoteCommandFailed.new(error.message, code)
        when Domain::ExitCode::CommandParse
          raise Domain::CommandParseError.new(error.message) if error.code == IPC::ErrorCode::COMMAND_PARSE_ERROR
          raise Domain::RemoteCommandFailed.new(error.message, code)
        when Domain::ExitCode::Config
          raise Domain::ConfigInvalid.new(error.message)
        else
          raise Domain::RemoteCommandFailed.new(error.message, code)
        end
      end

      private def next_id : String
        @sequence += 1
        "req-%06d" % @sequence
      end
    end
  end
end
