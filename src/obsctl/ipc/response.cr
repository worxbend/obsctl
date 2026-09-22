require "json"
require "../domain/errors"
require "../runtime/secret_redaction"

module Obsctl
  module IPC
    # Canonical public error-code taxonomy for server-to-client IPC failures.
    module ErrorCode
      CONFIG_INVALID        = "CONFIG_INVALID"
      SERVER_UNAVAILABLE    = "SERVER_UNAVAILABLE"
      OBS_UNAVAILABLE       = "OBS_UNAVAILABLE"
      REQUEST_TIMEOUT       = "REQUEST_TIMEOUT"
      OBS_REQUEST_FAILED    = "OBS_REQUEST_FAILED"
      SCENE_NOT_FOUND       = "SCENE_NOT_FOUND"
      AUDIO_INPUT_NOT_FOUND = "AUDIO_INPUT_NOT_FOUND"
      ALIAS_AMBIGUOUS       = "ALIAS_AMBIGUOUS"
      COMMAND_PARSE_ERROR   = "COMMAND_PARSE_ERROR"
      IPC_PROTOCOL_ERROR    = "IPC_PROTOCOL_ERROR"
      SHUTDOWN_DISABLED     = "SHUTDOWN_DISABLED"
      SERVER_ERROR          = "SERVER_ERROR"

      CODES = [
        CONFIG_INVALID,
        SERVER_UNAVAILABLE,
        OBS_UNAVAILABLE,
        REQUEST_TIMEOUT,
        OBS_REQUEST_FAILED,
        SCENE_NOT_FOUND,
        AUDIO_INPUT_NOT_FOUND,
        ALIAS_AMBIGUOUS,
        COMMAND_PARSE_ERROR,
        IPC_PROTOCOL_ERROR,
        SHUTDOWN_DISABLED,
        SERVER_ERROR,
      ]

      LEGACY_CODES = {
        "CONFIG_ERROR"    => CONFIG_INVALID,
        "REQUEST_FAILED"  => OBS_REQUEST_FAILED,
        "INTERNAL_ERROR"  => SERVER_ERROR,
        "INVALID_REQUEST" => IPC_PROTOCOL_ERROR,
      }

      def self.canonical(code : String) : String
        value = LEGACY_CODES[code]? || code
        raise Domain::IpcProtocolError.new("non-canonical IPC error code: #{code}") unless CODES.includes?(value)
        value
      end

      def self.for_exception(error : Domain::ObsctlError) : String
        case error
        when Domain::ConfigInvalid, Domain::ConfigNotFound
          CONFIG_INVALID
        when Domain::ServerUnavailable, Domain::IpcConnectionFailed
          SERVER_UNAVAILABLE
        when Domain::ObsUnavailable, Domain::ConnectionFailed, Domain::AuthenticationFailed
          OBS_UNAVAILABLE
        when Domain::RequestTimeout
          REQUEST_TIMEOUT
        when Domain::ObsRequestFailed
          OBS_REQUEST_FAILED
        when Domain::SceneNotFound
          SCENE_NOT_FOUND
        when Domain::AudioInputNotFound
          AUDIO_INPUT_NOT_FOUND
        when Domain::AliasAmbiguous
          ALIAS_AMBIGUOUS
        when Domain::ShutdownDisabled
          # Must precede `CommandParseError`, which it inherits from.
          SHUTDOWN_DISABLED
        when Domain::CommandParseError
          COMMAND_PARSE_ERROR
        when Domain::IpcProtocolError
          IPC_PROTOCOL_ERROR
        else
          SERVER_ERROR
        end
      end

      # The exit code a wire code maps to on the client side. This is the
      # taxonomy's mirror image: each code's exit code is the one carried by
      # the exception class it stands for (see `Domain::ExitCode.for_exception`
      # and the `exit_code` each class passes to its super), so this table and
      # `for_exception` describe one mapping from two directions and a new
      # code needs an entry in both.
      def self.exit_code(code : String) : Domain::ExitCode
        case code
        when SERVER_UNAVAILABLE, OBS_UNAVAILABLE, REQUEST_TIMEOUT
          Domain::ExitCode::Connection
        when COMMAND_PARSE_ERROR, SHUTDOWN_DISABLED, ALIAS_AMBIGUOUS
          Domain::ExitCode::CommandParse
        when CONFIG_INVALID
          Domain::ExitCode::Config
        when SCENE_NOT_FOUND, AUDIO_INPUT_NOT_FOUND, OBS_REQUEST_FAILED
          Domain::ExitCode::ObsRequest
        when IPC_PROTOCOL_ERROR
          Domain::ExitCode::Ipc
        else
          Domain::ExitCode::Failure
        end
      end
    end

    # Stable error payload returned for failed IPC command requests.
    class ErrorPayload
      getter code : String
      getter message : String

      def initialize(code : String, message : String)
        @code = ErrorCode.canonical(code)
        @message = self.class.sanitize_message(message)
      end

      def self.from_exception(error : Domain::ObsctlError) : self
        new(ErrorCode.for_exception(error), error.message || "request failed")
      end

      def self.server_error : self
        new(ErrorCode::SERVER_ERROR, "internal server error")
      end

      # Delegates to the shared ruleset so IPC error messages and log lines
      # cannot drift apart on what counts as a secret.
      def self.sanitize_message(message : String) : String
        Runtime::SecretRedaction.redact(message)
      end

      # Writes the wire-format JSON object for this error.
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "code", code
          json.field "message", message
        end
      end
    end

    # Command response correlated to a client request by request ID.
    record Response, id : String, ok : Bool, result : JSON::Any? = nil, error : ErrorPayload? = nil do
      TYPE = "response"

      # The failure this response describes, or nil when the command succeeded.
      #
      # The wire shape can express a combination that means nothing — `ok:
      # false` with no error to explain it — because `ok` and `error` are
      # separate fields and a peer is free to send either. Every client needs
      # the same answer to that: there is no message to show and no exit code
      # to derive, so it is a protocol violation. This is the one place that
      # decides so; callers used to each repeat the check and the wording, and
      # three copies of an invariant is three chances to word it differently or
      # forget it.
      def failure : ErrorPayload?
        return if ok

        error || raise Domain::IpcProtocolError.new("server returned an invalid error response")
      end

      # Writes the wire-format JSON object for this response.
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "id", id
          json.field "type", TYPE
          json.field "ok", ok
          json.field "result", result if result
          json.field "error", error if error
        end
      end
    end
  end
end
