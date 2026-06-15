require "json"

module Obsctl
  module IPC
    # Stable error payload returned for failed IPC command requests.
    record ErrorPayload, code : String, message : String do
      # Writes the wire-format JSON object for this error.
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "code", code
          json.field "message", message
        end
      end
    end

    # Command response correlated to a client request by request ID.
    record Response, id : String, ok : Bool, result : JSON::Any? = nil, error : ErrorPayload? = nil do
      TYPE = "response"

      # Writes the wire-format JSON object for this response.
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
