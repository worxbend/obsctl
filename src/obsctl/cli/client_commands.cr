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
        Domain::ExitCode.for_exception(remote_exception(error))
      end

      # Rebuilds the domain error a failed response stands for — the one place
      # the wire taxonomy becomes exception types again.
      #
      # Only the four codes whose classes carry the daemon's message verbatim
      # get their own type; `ServerUnavailable` additionally drives the
      # startup hint in `CLI::Main`. The rest become `RemoteCommandFailed`,
      # because classes like `RequestTimeout` format their own message and
      # would overwrite what the daemon said. Their exit code comes from the
      # wire code (`IPC::ErrorCode.exit_code`), so every remote failure's exit
      # code is derivable from the exception alone through
      # `Domain::ExitCode.for_exception` — there is no second table.
      def self.remote_exception(error : IPC::ErrorPayload) : Domain::ObsctlError
        case error.code
        when IPC::ErrorCode::SERVER_UNAVAILABLE
          Domain::ServerUnavailable.new(error.message)
        when IPC::ErrorCode::OBS_UNAVAILABLE
          Domain::ObsUnavailable.new(error.message)
        when IPC::ErrorCode::COMMAND_PARSE_ERROR
          Domain::CommandParseError.new(error.message)
        when IPC::ErrorCode::CONFIG_INVALID
          Domain::ConfigInvalid.new(error.message)
        else
          Domain::RemoteCommandFailed.new(error.message, IPC::ErrorCode.exit_code(error.code))
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
        when Domain::StatusCommand            then @presenter.combined_status(result)
        when Domain::ObsStatusCommand         then @presenter.obs_status(result)
        when Domain::ServerStatusCommand      then @presenter.server_status(result)
        when Domain::RecordStatusCommand      then @presenter.record_status(result)
        when Domain::ListSceneProfilesCommand then scene_profile_list(result)
        else                                       result["message"]?.try(&.as_s?) || "ok"
        end
      end

      # The one scene-profile command that answers with data rather than a
      # sentence. Marks the active profile and says how many scenes each hides,
      # so the listing answers "which one am I on" without a second command.
      private def scene_profile_list(result : JSON::Any) : String
        active = result["active"]?.try(&.as_s?)
        profiles = result["profiles"]?.try(&.as_a?) || [] of JSON::Any
        return "no scene profiles configured" if profiles.empty?

        profiles.join("\n") do |profile|
          name = profile["name"]?.try(&.as_s?) || ""
          hidden = profile["hidden"]?.try(&.as_a?).try(&.size) || 0
          "#{name == active ? "*" : " "} #{name} (hides #{hidden})"
        end
      end

      private def raise_remote_error(error : IPC::ErrorPayload) : NoReturn
        raise self.class.remote_exception(error)
      end

      private def next_id : String
        @sequence += 1
        "req-%06d" % @sequence
      end
    end
  end
end
