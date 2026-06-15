require "json"

module Obsctl
  module OBS
    module Protocol
      record Event, event_type : String, event_data : JSON::Any? do
        def self.from_frame(frame : String) : self?
          root = JSON.parse(frame)
          return nil unless root["op"].as_i == 5
          data = root["d"]
          new(data["eventType"].as_s, data["eventData"]?)
        end
      end
    end
  end
end
