require "json"
require "./opcode"

module Obsctl
  module OBS
    module Protocol
      # obs-websocket Request message with opcode 6.
      record Request, request_type : String, request_id : String, request_data : JSON::Any? = nil do
        # Serializes the request as an obs-websocket JSON frame.
        def to_frame : String
          JSON.build do |json|
            json.object do
              json.field "op", Opcode::Request.value
              json.field "d" do
                json.object do
                  json.field "requestType", request_type
                  json.field "requestId", request_id
                  if data = request_data
                    json.field "requestData", data
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
