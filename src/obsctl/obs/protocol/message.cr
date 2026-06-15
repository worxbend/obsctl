require "json"

module Obsctl
  module OBS
    module Protocol
      module Message
        def self.opcode(frame : String) : Int32
          JSON.parse(frame)["op"].as_i.to_i32
        end
      end
    end
  end
end
