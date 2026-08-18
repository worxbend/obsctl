module Obsctl
  module IPC
    # Every command name that may appear in an IPC `CommandPayload`.
    #
    # These are wire vocabulary, not CLI vocabulary: the CLI spells the scene
    # switch `scene` and the daemon spells it `set_scene`, and the two are
    # allowed to differ because they answer to different audiences. What is not
    # allowed is for the two ends of the wire to disagree with each other.
    #
    # Before these constants existed the same strings were written out by hand
    # in four places — the `Domain::Command` structs, the executor's `case`
    # arms, the TUI dispatcher, and the daemon's shutdown check — and nothing
    # connected them. A command added to one and forgotten in another compiled
    # and shipped, then failed at runtime with `unsupported IPC command`.
    # Referring to a constant makes a typo a compile error, and
    # `CommandExecutor::HANDLERS` is keyed by these same constants so the set
    # the daemon answers is checked against the set the clients can send
    # (`spec/obsctl/domain/command_ipc_coverage_spec.cr`).
    module CommandName
      PING                 = "ping"
      STATUS               = "status"
      GET_SERVER_STATUS    = "get_server_status"
      GET_OBS_STATUS       = "get_obs_status"
      GET_SNAPSHOT         = "get_snapshot"
      RECONNECT_OBS        = "reconnect_obs"
      SHUTDOWN_SERVER      = "shutdown_server"
      SET_SCENE            = "set_scene"
      SET_PROFILE          = "set_profile"
      SET_SCENE_COLLECTION = "set_scene_collection"
      MUTE                 = "mute"
      UNMUTE               = "unmute"
      TOGGLE_MUTE          = "toggle_mute"
      SET_VOLUME           = "set_volume"
      TOGGLE_STREAM        = "toggle_stream"
      TOGGLE_RECORD        = "toggle_record"
      START_RECORD         = "start_record"
      STOP_RECORD          = "stop_record"
      PAUSE_RECORD         = "pause_record"
      RESUME_RECORD        = "resume_record"
      RECORD_STATUS        = "record_status"
      VALIDATE_CONFIG      = "validate_config"
      DUMP_CONFIG          = "dump_config"
      RELOAD_CONFIG        = "reload_config"
    end
  end
end
