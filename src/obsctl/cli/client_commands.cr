require "json"
require "../domain/command"
require "../domain/command_result"
require "../domain/errors"
require "../ipc/protocol"
require "./color"

module Obsctl
  module CLI
    class ClientCommands
      def initialize(
        @client : IPC::UnixClient = IPC::UnixClient.new,
        @palette : Palette = Palette.monochrome,
      )
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
          if error = response.error
            raise_remote_error(error)
          end
          raise Domain::IpcProtocolError.new("server returned an invalid error response")
        end

        Domain::CommandResult.ok(format_response(command, response.result))
      end

      private def request_for(command : Domain::Command) : IPC::Request
        IPC::Request.new(next_id, IPC::Request::TYPE_COMMAND, payload_for(command))
      end

      # Commands carry their own IPC name and payload arguments, so there is no
      # table to keep in step with `Domain::CommandRegistry`.
      private def payload_for(command : Domain::Command) : IPC::CommandPayload
        name = command.ipc_name
        raise Domain::CommandParseError.new("unsupported CLI command") unless name

        IPC::CommandPayload.new(name, command.target, command.percent)
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
        when Domain::RecordStatusCommand
          format_record_status(result)
        else
          result["message"]?.try(&.as_s?) || "ok"
        end
      end

      private def format_record_status(result : JSON::Any) : String
        lines = [] of String
        lines << "recording: #{record_state_label(result)}"
        lines << "timecode: #{result["timecode"]?.try(&.as_s?) || "-"}"
        lines << "duration_ms: #{result["duration_ms"]?.try(&.as_i64?) || "-"}"
        lines << "bytes: #{result["bytes"]?.try(&.as_i64?) || "-"}"
        lines.join("\n")
      end

      private def record_state_label(result : JSON::Any) : String
        case result["active"]?.try(&.as_bool?)
        when true  then result["paused"]?.try(&.as_bool?) == true ? "paused" : "active"
        when false then "stopped"
        else            "-"
        end
      end

      private def format_combined_status(result : JSON::Any) : String
        server = result["server"]?
        obs = result["obs"]?
        return format_obs_status(result) unless server && obs

        bold = @palette.bold
        reset = @palette.reset
        [
          "#{bold}#{@palette.blue}── server ──────────────────────────#{reset}",
          indent(format_server_status(server)),
          "#{bold}#{@palette.cyan}── obs ─────────────────────────────#{reset}",
          indent(format_obs_status(obs)),
        ].join('\n')
      end

      private def format_obs_status(result : JSON::Any) : String
        dim = @palette.dim
        reset = @palette.reset
        heading = "#{@palette.bold}#{@palette.cyan}"

        lines = [] of String
        connected = result["connected"]?.try(&.as_bool?) || false
        if connected
          lines << "#{@palette.green}● connected#{reset}"
        else
          lines << "#{@palette.red}○ disconnected#{reset}"
        end
        lines << "current_scene: #{@palette.bright_white}#{result["current_scene"]?.try(&.as_s?) || "-"}#{reset}"
        lines << "#{heading}Scenes:#{reset}"
        result["scenes"]?.try(&.as_a?).try do |scenes|
          scenes.each do |scene|
            active = scene["active"]?.try(&.as_bool?) || false
            if active
              lines << "  #{@palette.bold}#{@palette.green}▶ #{scene["name"].as_s}#{reset}"
            else
              lines << "    #{scene["name"].as_s}"
            end
          end
        end
        lines << "#{heading}Audio:#{reset}"
        result["audio_inputs"]?.try(&.as_a?).try do |inputs|
          inputs.each do |input|
            muted = input["muted"]?.try(&.as_bool?)
            volume_pct = input["volume_percent"]?.try(&.as_i?) || 0
            volume_bar = volume_bar(volume_pct)
            if muted.nil?
              lines << "  #{dim}? #{input["name"].as_s} unknown#{reset}"
            elsif muted
              lines << "  #{dim}#{@palette.red}✕ #{input["name"].as_s}#{reset} #{dim}muted#{reset} #{volume_bar}"
            else
              lines << "  #{@palette.green}♪#{reset} #{input["name"].as_s} #{volume_bar}"
            end
          end
        end
        lines.join('\n')
      end

      private def volume_bar(percent : Int32) : String
        filled = (percent / 10).clamp(0, 10).to_i
        empty = 10 - filled
        bar = "█" * filled + "░" * empty
        dim = @palette.dim
        reset = @palette.reset
        "#{dim}[#{reset}#{bar}#{dim}]#{reset} #{percent}%"
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
        lines << "dropped_reconnect_diagnostic_logs: #{optional_integer_text(result["dropped_reconnect_diagnostic_logs"]?)}"
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

      private def optional_integer_text(value : JSON::Any?) : String
        value.try(&.as_i64?).try(&.to_s) || "-"
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
