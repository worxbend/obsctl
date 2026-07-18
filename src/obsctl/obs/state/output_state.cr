module Obsctl
  module OBS
    module State
      # Authoritative stream/record output state queried from OBS and updated by events.
      record OutputState,
        streaming : Bool? = nil,
        recording : Bool? = nil
    end
  end
end
