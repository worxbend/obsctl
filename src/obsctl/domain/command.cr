module Obsctl
  module Domain
    abstract struct Command
    end

    struct HelpCommand < Command
    end

    struct QuitCommand < Command
    end

    struct DumpConfigCommand < Command
    end

    struct ReloadConfigCommand < Command
    end

    struct StatusCommand < Command
    end

    struct ServerStatusCommand < Command
    end

    struct ObsStatusCommand < Command
    end

    struct ValidateConfigCommand < Command
    end

    struct ReconnectCommand < Command
    end

    struct ShutdownServerCommand < Command
    end

    struct ConnectCommand < Command
    end

    struct DisconnectCommand < Command
    end

    struct SetSceneCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    struct MuteCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    struct UnmuteCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    struct ToggleMuteCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    struct VolumeCommand < Command
      getter target, percent

      def initialize(@target : String, @percent : Int32)
      end
    end
  end
end
