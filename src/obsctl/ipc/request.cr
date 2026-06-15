require "json"

module Obsctl
  module IPC
    # Typed command payload sent by CLI and TUI clients to the local daemon.
    record CommandPayload, name : String, target : String? = nil, percent : Int32? = nil do
      # Writes the wire-format JSON object for this command payload.
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "name", name
          json.field "target", target if target
          json.field "percent", percent if percent
        end
      end
    end

    # A single newline-delimited IPC request received by the daemon.
    #
    # Requests are either command invocations or long-lived topic subscriptions.
    record Request, id : String, type : String, command : CommandPayload? = nil, topics : Array(String) = [] of String do
      TYPE_COMMAND   = "command"
      TYPE_SUBSCRIBE = "subscribe"

      # Returns true when this request carries a command payload.
      def command? : Bool
        type == TYPE_COMMAND
      end

      # Returns true when this request asks the server to register topic pushes.
      def subscribe? : Bool
        type == TYPE_SUBSCRIBE
      end

      # Writes the wire-format JSON object for this request.
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
