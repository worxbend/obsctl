module Obsctl
  module OBS
    module State
      # Stream/record output state placeholder for future controls.
      record OutputState,
        streaming : Bool? = nil,
        recording : Bool? = nil
    end
  end
end
