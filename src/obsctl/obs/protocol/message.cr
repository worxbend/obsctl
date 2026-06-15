require "json"

module Obsctl
  module OBS
    module Protocol
      # Shared helpers for reading raw obs-websocket message frames.
      module Message
        # Extracts the numeric obs-websocket opcode from a JSON frame.
        def self.opcode(frame : String) : Int32
          JSON.parse(frame)["op"].as_i.to_i32
        end
      end
    end
  end
end
