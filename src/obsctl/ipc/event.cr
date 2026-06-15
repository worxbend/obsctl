require "json"

module Obsctl
  module IPC
    record Event, topic : String, data : JSON::Any? = nil do
      TYPE = "event"

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
