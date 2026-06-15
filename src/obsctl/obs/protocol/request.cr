require "json"

module Obsctl
  module OBS
    module Protocol
      record Request, request_type : String, request_id : String, request_data : JSON::Any? = nil do
        def to_frame : String
          JSON.build do |json|
            json.object do
              json.field "op", 6
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
