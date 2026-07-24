module Obsctl
  module Domain
    # Base type for parsed CLI commands.
    abstract struct Command
    end

    # Displays command help.
    struct HelpCommand < Command
    end

    # Requests the current interactive session to exit.
    struct QuitCommand < Command
    end

    # Requests a server-side config dump from OBS state.
    struct DumpConfigCommand < Command
    end

    # Requests the server to reload config from disk.
    struct ReloadConfigCommand < Command
    end

    # Requests the combined server and OBS status.
    struct StatusCommand < Command
    end

    # Requests local daemon status only.
    struct ServerStatusCommand < Command
    end

    # Requests OBS connection/status details through the server.
    struct ObsStatusCommand < Command
    end

    # Requests server-side config validation.
    struct ValidateConfigCommand < Command
    end

    # Requests the server-owned OBS supervisor to reconnect.
    struct ReconnectCommand < Command
    end

    # Requests server shutdown; execution remains config-guarded server-side.
    struct ShutdownServerCommand < Command
    end

    # Requests an interactive session to connect.
    struct ConnectCommand < Command
    end

    # Requests an interactive session to disconnect.
    struct DisconnectCommand < Command
    end

    # Changes the current OBS program scene by alias, shortcut, or OBS name.
    struct SetSceneCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    struct SetProfileCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    struct SetSceneCollectionCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    # Mutes an OBS audio input resolved by alias, shortcut, or OBS name.
    struct MuteCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    # Unmutes an OBS audio input resolved by alias, shortcut, or OBS name.
    struct UnmuteCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    # Toggles mute for an OBS audio input.
    struct ToggleMuteCommand < Command
      getter target

      def initialize(@target : String)
      end
    end

    # Sets user-facing volume percentage for an OBS audio input.
    struct VolumeCommand < Command
      getter target, percent

      def initialize(@target : String, @percent : Int32)
      end
    end

    struct ToggleStreamCommand < Command
    end

    struct ToggleRecordCommand < Command
    end

    # Starts the OBS recording output. Starting while already recording is a
    # no-op in OBS, so the daemon reports the resulting state rather than
    # failing.
    struct StartRecordCommand < Command
    end

    # Stops the OBS recording output and reports the written file path.
    struct StopRecordCommand < Command
    end

    struct PauseRecordCommand < Command
    end

    struct ResumeRecordCommand < Command
    end

    # Reports record active/paused state, timecode, duration, and size.
    struct RecordStatusCommand < Command
    end
  end
end
