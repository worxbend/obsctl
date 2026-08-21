require "json"

module Obsctl
  module OBS
    module Protocol
      # Shared helpers for reading raw obs-websocket message frames.
      module Message
        # Parses a raw frame into its JSON root.
        #
        # The root is handed on to `Response.from_data`/`Event.from_data`
        # rather than each of them re-parsing the same text: classifying a
        # frame by its `op` and reading its `d` are two halves of one pass.
        def self.parse(frame : String) : JSON::Any
          JSON.parse(frame)
        end
      end
    end
  end
end
