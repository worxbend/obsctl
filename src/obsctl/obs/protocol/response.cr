require "json"
require "./opcode"

module Obsctl
  module OBS
    module Protocol
      # Status object nested inside obs-websocket RequestResponse frames.
      record RequestStatus, result : Bool, code : Int32?, comment : String?

      # Parsed obs-websocket RequestResponse message with opcode 7.
      record Response,
        request_type : String,
        request_id : String,
        request_status : RequestStatus,
        response_data : JSON::Any? do
        # Reads a response out of an already-parsed frame whose `op` the
        # caller has established is `RequestResponse`.
        def self.from_data(root : JSON::Any) : self
          data = root["d"]
          status = data["requestStatus"]
          new(
            data["requestType"].as_s,
            data["requestId"].as_s,
            RequestStatus.new(
              status["result"].as_bool,
              status["code"]?.try(&.as_i).try(&.to_i32),
              status["comment"]?.try(&.as_s)
            ),
            data["responseData"]?
          )
        end
      end
    end
  end
end
