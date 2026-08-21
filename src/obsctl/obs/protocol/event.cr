require "json"
require "./opcode"

module Obsctl
  module OBS
    module Protocol
      # Parsed obs-websocket Event message with opcode 5.
      record Event, event_type : String, event_data : JSON::Any? do
        # Reads an event out of an already-parsed frame whose `op` the caller
        # has established is `Event`.
        def self.from_data(root : JSON::Any) : self
          data = root["d"]
          new(data["eventType"].as_s, data["eventData"]?)
        end
      end
    end
  end
end
