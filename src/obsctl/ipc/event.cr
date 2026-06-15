require "json"

module Obsctl
  module IPC
    # Server-pushed topic event for subscribed TUI or long-lived clients.
    record Event, topic : String, data : JSON::Any? = nil do
      TYPE = "event"

      # Writes the wire-format JSON object for this event.
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "type", TYPE
          json.field "topic", topic
          json.field "data", data if data
        end
      end
    end
  end
end
