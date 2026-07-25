module Obsctl
  module Domain
    # Base type for parsed CLI commands.
    #
    # A command knows its own IPC identity and payload arguments, so every
    # surface that has to put one on the wire — the thin CLI client and the TUI
    # dispatcher — builds the payload the same way instead of maintaining its
    # own type-to-name table.
    abstract struct Command
      # IPC command name, or nil for commands resolved entirely client-side.
      def ipc_name : String?
        nil
      end

      # Payload target, for commands that address a named OBS resource.
      def target : String?
        nil
      end

      # Payload percentage, for commands that carry a level.
      def percent : Int32?
        nil
      end
    end

    # Displays command help.
    struct HelpCommand < Command
    end

    # Requests the current interactive session to exit.
    struct QuitCommand < Command
    end

    # Requests a server-side config dump from OBS state.
    struct DumpConfigCommand < Command
      def ipc_name : String?
        "dump_config"
      end
    end

    # Requests the server to reload config from disk.
    struct ReloadConfigCommand < Command
      def ipc_name : String?
        "reload_config"
      end
    end

    # Requests the combined server and OBS status.
    struct StatusCommand < Command
      def ipc_name : String?
        "status"
      end
    end

    # Requests local daemon status only.
    struct ServerStatusCommand < Command
      def ipc_name : String?
        "get_server_status"
      end
    end

    # Requests OBS connection/status details through the server.
    struct ObsStatusCommand < Command
      def ipc_name : String?
        "get_obs_status"
      end
    end

    # Requests server-side config validation.
    struct ValidateConfigCommand < Command
      def ipc_name : String?
        "validate_config"
      end
    end

    # Requests the server-owned OBS supervisor to reconnect.
    struct ReconnectCommand < Command
      def ipc_name : String?
        "reconnect_obs"
      end
    end

    # Requests server shutdown; execution remains config-guarded server-side.
    struct ShutdownServerCommand < Command
      def ipc_name : String?
        "shutdown_server"
      end
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

      def ipc_name : String?
        "set_scene"
      end
    end

    struct SetProfileCommand < Command
      getter target

      def initialize(@target : String)
      end

      def ipc_name : String?
        "set_profile"
      end
    end

    struct SetSceneCollectionCommand < Command
      getter target

      def initialize(@target : String)
      end

      def ipc_name : String?
        "set_scene_collection"
      end
    end

    # Mutes an OBS audio input resolved by alias, shortcut, or OBS name.
    struct MuteCommand < Command
      getter target

      def initialize(@target : String)
      end

      def ipc_name : String?
        "mute"
      end
    end

    # Unmutes an OBS audio input resolved by alias, shortcut, or OBS name.
    struct UnmuteCommand < Command
      getter target

      def initialize(@target : String)
      end

      def ipc_name : String?
        "unmute"
      end
    end

    # Toggles mute for an OBS audio input.
    struct ToggleMuteCommand < Command
      getter target

      def initialize(@target : String)
      end

      def ipc_name : String?
        "toggle_mute"
      end
    end

    # Sets user-facing volume percentage for an OBS audio input.
    struct VolumeCommand < Command
      getter target, percent

      def initialize(@target : String, @percent : Int32)
      end

      def ipc_name : String?
        "set_volume"
      end
    end

    struct ToggleStreamCommand < Command
      def ipc_name : String?
        "toggle_stream"
      end
    end

    struct ToggleRecordCommand < Command
      def ipc_name : String?
        "toggle_record"
      end
    end

    # Starts the OBS recording output. Starting while already recording is a
    # no-op in OBS, so the daemon reports the resulting state rather than
    # failing.
    struct StartRecordCommand < Command
      def ipc_name : String?
        "start_record"
      end
    end

    # Stops the OBS recording output and reports the written file path.
    struct StopRecordCommand < Command
      def ipc_name : String?
        "stop_record"
      end
    end

    struct PauseRecordCommand < Command
      def ipc_name : String?
        "pause_record"
      end
    end

    struct ResumeRecordCommand < Command
      def ipc_name : String?
        "resume_record"
      end
    end

    # Reports record active/paused state, timecode, duration, and size.
    struct RecordStatusCommand < Command
      def ipc_name : String?
        "record_status"
      end
    end
  end
end
