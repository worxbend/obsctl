require "../obs/state/obs_snapshot"

module Obsctl
  module TUI
    record Model,
      snapshot : OBS::State::ObsSnapshot?,
      command_line : String = "",
      last_result : String? = nil,
      logs : Array(String) = [] of String
  end
end
