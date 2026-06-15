require "json"

module Obsctl
  module IPC
    record ErrorPayload, code : String, message : String do
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "code", code
          json.field "message", message
        end
      end
    end

    record Response, id : String, ok : Bool, result : JSON::Any? = nil, error : ErrorPayload? = nil do
      TYPE = "response"

      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "id", id
          json.field "type", TYPE
          json.field "ok", ok
          json.field "result", result if result
          json.field "error", error if error
        end
      end
    end
  end
end
