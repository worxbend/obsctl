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

    # Raised when a local or OBS connection cannot be established or maintained.
    class ConnectionFailed < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::Connection)
      end
    end

    # Raised when obs-websocket authentication fails.
    class AuthenticationFailed < ObsctlError
      def initialize(message = "OBS authentication failed")
        super(message, ExitCode::Connection)
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
      def initialize(message = "OBS is unavailable")
        super(message, ExitCode::Connection)
      end
    end

    # Raised when a thin client cannot reach the local obsctl server.
    class ServerUnavailable < ObsctlError
      def initialize(message = "obsctl server is not running")
        super(message, ExitCode::Connection)
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

    # Raised when CLI or TUI command text cannot be parsed.
    class CommandParseError < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::CommandParse)
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
