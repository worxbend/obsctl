module Obsctl
  module Domain
    # Process exit codes used by CLI, IPC, and domain error boundaries.
    enum ExitCode
      Success      = 0
      Failure      = 1
      Config       = 2
      Connection   = 3
      ObsRequest   = 4
      CommandParse = 5
      Ipc          = 6
    end

    # Base error type with a stable process exit-code mapping.
    abstract class ObsctlError < Exception
      getter exit_code

      def initialize(message : String, @exit_code : ExitCode)
        super(message)
      end
    end

    # Raised when the requested config file does not exist.
    class ConfigNotFound < ObsctlError
      def initialize(path : String)
        super("config not found: #{path}", ExitCode::Config)
      end
    end

    # Raised when config content is syntactically or semantically invalid.
    class ConfigInvalid < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::Config)
      end
    end

    # Why an OBS connection ended.
    #
    # This exists so the daemon can label a disconnect in its logs without
    # reading its own error messages back. The log codes operators build alerts
    # on used to be derived by matching regular expressions against the
    # exception's message text, which meant rewording a diagnostic — for
    # clarity, say — silently renamed the log code. The kind is set once, where
    # the cause is actually known, and the message stays free to change.
    enum DisconnectKind
      # No more specific cause; the socket ended or never came up.
      Disconnected
      # The peer sent a frame this client could not parse at all.
      MalformedFrame
      # A response frame arrived but could not be read as a response.
      ResponseParserError
      # obsctl asked for the close, so this is not a fault.
      ClosedCleanly

      # The `code` field used in daemon log entries for this cause.
      def log_code : String
        case self
        in Disconnected        then "obs_disconnected"
        in MalformedFrame      then "obs_malformed_frame"
        in ResponseParserError then "obs_response_parser_error"
        in ClosedCleanly       then "obs_closed_cleanly"
        end
      end
    end

    # Raised when a local or OBS connection cannot be established or maintained.
    class ConnectionFailed < ObsctlError
      # What ended the connection. Defaults to the unspecific case so callers
      # that have nothing more to say do not have to invent something.
      getter kind : DisconnectKind

      def initialize(message : String, @kind : DisconnectKind = DisconnectKind::Disconnected)
        super(message, ExitCode::Connection)
      end
    end

    # Raised when obs-websocket authentication fails.
    class AuthenticationFailed < ObsctlError
      DEFAULT_MESSAGE = "OBS authentication failed"

      # Accepts a nilable message because most call sites forward
      # `some_exception.message`, which is `String?`.
      def initialize(message : String? = nil)
        super(message || DEFAULT_MESSAGE, ExitCode::Connection)
      end
    end

    # Raised when OBS does not answer within the configured request timeout.
    class RequestTimeout < ObsctlError
      def initialize(request_type : String)
        super("OBS request timed out: #{request_type}", ExitCode::Connection)
      end
    end

    # Raised when OBS returns an unsuccessful request status.
    class ObsRequestFailed < ObsctlError
      def initialize(request_type : String, message : String)
        super("OBS request failed for #{request_type}: #{message}", ExitCode::ObsRequest)
      end
    end

    # Raised when the local server is alive but OBS is currently disconnected.
    class ObsUnavailable < ObsctlError
      DEFAULT_MESSAGE = "OBS is unavailable"

      def initialize(message : String? = nil)
        super(message || DEFAULT_MESSAGE, ExitCode::Connection)
      end
    end

    # Raised when a thin client cannot reach the local obsctl server.
    class ServerUnavailable < ObsctlError
      DEFAULT_MESSAGE = "obsctl server is not running"

      def initialize(message : String? = nil)
        super(message || DEFAULT_MESSAGE, ExitCode::Connection)
      end
    end

    # Raised by thin clients for server-side command failures.
    class RemoteCommandFailed < ObsctlError
      def initialize(message : String, exit_code : ExitCode)
        super(message, exit_code)
      end
    end

    # Raised when a scene target cannot be resolved.
    class SceneNotFound < ObsctlError
      def initialize(target : String)
        super("scene not found: #{target}", ExitCode::ObsRequest)
      end
    end

    # Raised when an audio target cannot be resolved.
    class AudioInputNotFound < ObsctlError
      def initialize(target : String)
        super("audio input not found: #{target}", ExitCode::ObsRequest)
      end
    end

    # Raised when alias/shortcut/name resolution matches multiple entries.
    class AliasAmbiguous < ObsctlError
      def initialize(kind : String, target : String)
        super("#{kind} lookup is ambiguous: #{target}", ExitCode::CommandParse)
      end
    end

    # Raised when CLI command text cannot be parsed.
    class CommandParseError < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::CommandParse)
      end
    end

    # Raised when `shutdown_server` is refused by `server.allow_remote_shutdown`.
    #
    # A subclass of `CommandParseError` so it keeps the same exit code and is
    # still caught by everything that handles a rejected command. It exists as
    # its own type because the IPC layer has to map it to the public
    # `SHUTDOWN_DISABLED` error code, and matching a type is something the
    # compiler checks — matching the wording of a message is not.
    class ShutdownDisabled < CommandParseError
      DEFAULT_MESSAGE = "remote shutdown is disabled"

      def initialize(message : String? = nil)
        super(message || DEFAULT_MESSAGE)
      end
    end

    # Raised when Unix socket IPC cannot connect or continue.
    class IpcConnectionFailed < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::Ipc)
      end
    end

    # Raised when a local IPC peer sends unexpected protocol data.
    class IpcProtocolError < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::Ipc)
      end
    end

    # Raised when systemd user service installation or control fails.
    class ServiceInstallFailed < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::Failure)
      end
    end
  end
end
