require "json"
require "../domain/command"
require "../domain/command_result"
require "../domain/errors"
require "../ipc/protocol"
require "./color"
require "./status_presenter"

module Obsctl
  module CLI
    class ClientCommands
      def initialize(
        @client : IPC::UnixClient = IPC::UnixClient.new,
        palette : Palette = Palette.monochrome,
      )
        @presenter = StatusPresenter.new(palette)
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
        # Rejects a malformed failure here so every caller can trust that an
        # unsuccessful response has something to say about why.
        response.failure
        response
      rescue Domain::IpcConnectionFailed
        raise Domain::ServerUnavailable.new
      end

      def execute(command : Domain::Command) : Domain::CommandResult
        response = request(command)
        if error = response.failure
          raise_remote_error(error)
        end

        Domain::CommandResult.ok(format_response(command, response.result))
      end

      # Commands build their own payload, so there is no table here to keep in
      # step with `Domain::CommandRegistry`.
      private def request_for(command : Domain::Command) : IPC::Request
        IPC::Request.new(next_id, IPC::Request::TYPE_COMMAND, command.to_payload)
      end

      # Turns a successful response into the line(s) the user sees.
      #
      # Only the status-shaped commands need real rendering; every other
      # command answers with a `message` the daemon already worded.
      private def format_response(command : Domain::Command, result : JSON::Any?) : String
        return "ok" unless result

        case command
        when Domain::StatusCommand       then @presenter.combined_status(result)
        when Domain::ObsStatusCommand    then @presenter.obs_status(result)
        when Domain::ServerStatusCommand then @presenter.server_status(result)
        when Domain::RecordStatusCommand then @presenter.record_status(result)
        else                                  result["message"]?.try(&.as_s?) || "ok"
        end
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
