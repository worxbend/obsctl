module Obsctl
  module Domain
    enum ExitCode
      Success      = 0
      Failure      = 1
      Config       = 2
      Connection   = 3
      ObsRequest   = 4
      CommandParse = 5
      Ipc          = 6
    end

    abstract class ObsctlError < Exception
      getter exit_code

      def initialize(message : String, @exit_code : ExitCode)
        super(message)
      end
    end

    class ConfigNotFound < ObsctlError
      def initialize(path : String)
        super("config not found: #{path}", ExitCode::Config)
      end
    end

    class ConfigInvalid < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::Config)
      end
    end

    class ConnectionFailed < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::Connection)
      end
    end

    class AuthenticationFailed < ObsctlError
      def initialize(message = "OBS authentication failed")
        super(message, ExitCode::Connection)
      end
    end

    class RequestTimeout < ObsctlError
      def initialize(request_type : String)
        super("OBS request timed out: #{request_type}", ExitCode::Connection)
      end
    end

    class ObsRequestFailed < ObsctlError
      def initialize(request_type : String, message : String)
        super("OBS request failed for #{request_type}: #{message}", ExitCode::ObsRequest)
      end
    end

    class SceneNotFound < ObsctlError
      def initialize(target : String)
        super("scene not found: #{target}", ExitCode::ObsRequest)
      end
    end

    class AudioInputNotFound < ObsctlError
      def initialize(target : String)
        super("audio input not found: #{target}", ExitCode::ObsRequest)
      end
    end

    class AliasAmbiguous < ObsctlError
      def initialize(kind : String, target : String)
        super("#{kind} lookup is ambiguous: #{target}", ExitCode::CommandParse)
      end
    end

    class CommandParseError < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::CommandParse)
      end
    end

    class IpcConnectionFailed < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::Ipc)
      end
    end

    class IpcProtocolError < ObsctlError
      def initialize(message : String)
        super(message, ExitCode::Ipc)
      end
    end
  end
end
