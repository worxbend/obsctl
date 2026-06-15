require "json"

module Obsctl
  module IPC
    record CommandPayload, name : String, target : String? = nil, percent : Int32? = nil do
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "name", name
          json.field "target", target if target
          json.field "percent", percent if percent
        end
      end
    end

    record Request, id : String, type : String, command : CommandPayload? = nil, topics : Array(String) = [] of String do
      TYPE_COMMAND   = "command"
      TYPE_SUBSCRIBE = "subscribe"

      def command? : Bool
        type == TYPE_COMMAND
      end

      def subscribe? : Bool
        type == TYPE_SUBSCRIBE
      end

      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "id", id
          json.field "type", type
          json.field "command", command if command
          unless topics.empty?
            json.field "topics", topics
          end
        end
      end
    end
  end
end
