module Obsctl
  module OBS
    module State
      # Snapshot row for one OBS audio input.
      record AudioState,
        name : String,
        alias : String? = nil,
        shortcut : String? = nil,
        muted : Bool? = nil,
        volume_mul : Float64? = nil,
        volume_db : Float64? = nil,
        volume_percent : Int32? = nil
    end
  end
end
