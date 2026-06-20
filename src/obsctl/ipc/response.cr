require "json"
require "../domain/errors"

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
        when Domain::CommandParseError
          error.message == "remote shutdown is disabled" ? SHUTDOWN_DISABLED : COMMAND_PARSE_ERROR
        when Domain::IpcProtocolError
          IPC_PROTOCOL_ERROR
        else
          SERVER_ERROR
        end
      end
    end

    # Stable error payload returned for failed IPC command requests.
    class ErrorPayload
      SENSITIVE_KEY_PATTERN   = "(?:password|authentication(?:[ _-]?string)?|auth(?:[ _-]?string)?|token|secret)"
      SENSITIVE_VALUE_PATTERN = "(?:\"[^\"]*\"|'[^']*'|\\S+)"

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

      def self.sanitize_message(message : String) : String
        message
          .gsub(Regex.new("(?i)\\b(#{SENSITIVE_KEY_PATTERN})\\s*=\\s*#{SENSITIVE_VALUE_PATTERN}"), "\\1=[redacted]")
          .gsub(Regex.new("(?i)\\b(#{SENSITIVE_KEY_PATTERN})\\s*:\\s*#{SENSITIVE_VALUE_PATTERN}"), "\\1: [redacted]")
          .gsub(Regex.new("(?i)\\b(#{SENSITIVE_KEY_PATTERN})\\s+(\"[^\"]*\"|'[^']*')"), "\\1 [redacted]")
          .gsub(Regex.new("(?i)\\b(#{SENSITIVE_KEY_PATTERN})\\s+(is|was|equals|set to|configured as|provided as)\\s+#{SENSITIVE_VALUE_PATTERN}"), "\\1 \\2 [redacted]")
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
