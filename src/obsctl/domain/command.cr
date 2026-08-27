require "../ipc/command_name"
require "../ipc/request"
require "./errors"

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

      # Builds the IPC payload that asks the daemon to run this command.
      #
      # Both surfaces that talk to the daemon — the thin CLI client and the
      # TUI dispatcher — used to assemble this themselves from `ipc_name`,
      # `target`, and `percent`. Doing it here is what makes the claim in the
      # comment above true: there is one description of how a parsed command
      # becomes a request, so the two surfaces cannot send different things
      # for the same command.
      #
      # Raises when the command has no IPC name, which means it is resolved
      # entirely client-side (`help`, `quit`) and was never meant to be sent.
      def to_payload : IPC::CommandPayload
        name = ipc_name
        raise CommandParseError.new("command has no daemon equivalent") unless name

        IPC::CommandPayload.new(name: name, target: target, percent: percent)
      end
    end

    # Declares a daemon command whose only distinguishing feature is its IPC
    # name. One declaration per command — the same idea as the `config_value`
    # macro — so a command's IPC identity cannot drift between hand-written
    # copies of the same three-line struct.
    macro daemon_command(type_name, ipc_constant)
      struct {{ type_name }} < Command
        def ipc_name : String?
          {{ ipc_constant }}
        end
      end
    end

    # Declares a daemon command that addresses one named OBS resource: the
    # same shape as `daemon_command` plus the target getter/initializer pair,
    # declared once here for the same no-drift reason.
    macro targeted_daemon_command(type_name, ipc_constant)
      struct {{ type_name }} < Command
        getter target

        def initialize(@target : String)
        end

        def ipc_name : String?
          {{ ipc_constant }}
        end
      end
    end

    # Displays command help.
    struct HelpCommand < Command
    end

    # Requests the current interactive session to exit.
    struct QuitCommand < Command
    end

    # Requests a server-side config dump from OBS state.
    daemon_command DumpConfigCommand, IPC::CommandName::DUMP_CONFIG

    # Requests the server to reload config from disk.
    daemon_command ReloadConfigCommand, IPC::CommandName::RELOAD_CONFIG

    # Puts a saved scene profile into effect, so the scene list is filtered to
    # the scenes that profile leaves visible.
    targeted_daemon_command SetSceneProfileCommand, IPC::CommandName::SET_SCENE_PROFILE

    # Switches scene-profile filtering off, putting every scene back in the
    # list. Its own command rather than a `set` with an empty target -- see
    # `IPC::CommandName::CLEAR_SCENE_PROFILE`.
    daemon_command ClearSceneProfileCommand, IPC::CommandName::CLEAR_SCENE_PROFILE

    # Creates or replaces a saved scene profile.
    #
    # The only command whose payload carries a list, which is why it overrides
    # `to_payload` outright instead of just naming its `target`.
    #
    # `target` is the name the profile will have after the save and
    # `rename_from` names the existing profile being replaced, which is what
    # makes a rename one command rather than a save followed by a delete. That
    # matters because deleting a profile switches it off when it was the active
    # one, so the two-command form silently stopped hiding scenes whenever the
    # profile being renamed was the one in effect.
    struct SaveSceneProfileCommand < Command
      getter target
      getter hidden : Array(String)
      getter rename_from : String?

      def initialize(@target : String, @hidden : Array(String), @rename_from : String? = nil)
      end

      def ipc_name : String?
        IPC::CommandName::SAVE_SCENE_PROFILE
      end

      def to_payload : IPC::CommandPayload
        IPC::CommandPayload.new(
          name: IPC::CommandName::SAVE_SCENE_PROFILE,
          hidden: @hidden,
          rename_from: @rename_from,
          target: @target
        )
      end
    end

    # Removes a saved scene profile, switching filtering off when it was the
    # one in effect.
    targeted_daemon_command DeleteSceneProfileCommand, IPC::CommandName::DELETE_SCENE_PROFILE

    # Reports every saved scene profile and which one is in effect.
    daemon_command ListSceneProfilesCommand, IPC::CommandName::LIST_SCENE_PROFILES

    # Requests the combined server and OBS status.
    daemon_command StatusCommand, IPC::CommandName::STATUS

    # Requests local daemon status only.
    daemon_command ServerStatusCommand, IPC::CommandName::GET_SERVER_STATUS

    # Requests OBS connection/status details through the server.
    daemon_command ObsStatusCommand, IPC::CommandName::GET_OBS_STATUS

    # Requests server-side config validation.
    daemon_command ValidateConfigCommand, IPC::CommandName::VALIDATE_CONFIG

    # Requests the server-owned OBS supervisor to reconnect.
    daemon_command ReconnectCommand, IPC::CommandName::RECONNECT_OBS

    # Requests server shutdown; execution remains config-guarded server-side.
    daemon_command ShutdownServerCommand, IPC::CommandName::SHUTDOWN_SERVER

    # Requests an interactive session to connect.
    struct ConnectCommand < Command
    end

    # Requests an interactive session to disconnect.
    struct DisconnectCommand < Command
    end

    # Changes the current OBS program scene by alias, shortcut, or OBS name.
    targeted_daemon_command SetSceneCommand, IPC::CommandName::SET_SCENE

    targeted_daemon_command SetProfileCommand, IPC::CommandName::SET_PROFILE

    targeted_daemon_command SetSceneCollectionCommand, IPC::CommandName::SET_SCENE_COLLECTION

    # Mutes an OBS audio input resolved by alias, shortcut, or OBS name.
    targeted_daemon_command MuteCommand, IPC::CommandName::MUTE

    # Unmutes an OBS audio input resolved by alias, shortcut, or OBS name.
    targeted_daemon_command UnmuteCommand, IPC::CommandName::UNMUTE

    # Toggles mute for an OBS audio input.
    targeted_daemon_command ToggleMuteCommand, IPC::CommandName::TOGGLE_MUTE

    # Sets user-facing volume percentage for an OBS audio input.
    struct VolumeCommand < Command
      getter target, percent

      def initialize(@target : String, @percent : Int32)
      end

      def ipc_name : String?
        IPC::CommandName::SET_VOLUME
      end
    end

    daemon_command ToggleStreamCommand, IPC::CommandName::TOGGLE_STREAM

    daemon_command ToggleRecordCommand, IPC::CommandName::TOGGLE_RECORD

    # Starts the OBS recording output. Starting while already recording is a
    # no-op in OBS, so the daemon reports the resulting state rather than
    # failing.
    daemon_command StartRecordCommand, IPC::CommandName::START_RECORD

    # Stops the OBS recording output and reports the written file path.
    daemon_command StopRecordCommand, IPC::CommandName::STOP_RECORD

    daemon_command PauseRecordCommand, IPC::CommandName::PAUSE_RECORD

    daemon_command ResumeRecordCommand, IPC::CommandName::RESUME_RECORD

    # Reports record active/paused state, timecode, duration, and size.
    daemon_command RecordStatusCommand, IPC::CommandName::RECORD_STATUS
  end
end
