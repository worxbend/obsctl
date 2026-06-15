module Obsctl
  module OBS
    module State
      record OutputState,
        streaming : Bool? = nil,
        recording : Bool? = nil
    end
  end
end
