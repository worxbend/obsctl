module Obsctl
  module OBS
    module Protocol
      enum Opcode
        Hello           = 0
        Identify        = 1
        Identified      = 2
        Reidentify      = 3
        Event           = 5
        Request         = 6
        RequestResponse = 7
      end
    end
  end
end
