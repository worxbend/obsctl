module Obsctl
  module OBS
    module State
      # Snapshot row for one OBS scene.
      record SceneState,
        name : String,
        alias : String? = nil,
        shortcut : String? = nil,
        group : String? = nil,
        active : Bool = false
    end
  end
end
