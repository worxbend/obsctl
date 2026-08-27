require "json"

module Obsctl
  module IPC
    # Typed command payload sent by CLI clients to the local daemon.
    # Field order matters on the wire: obsctl-rs flattens its argument map next
    # to `name`, and a `serde_json` map serializes its keys alphabetically, so
    # the arguments follow `name` in alphabetical order. Emitting them in that
    # same order is what keeps a request byte-identical between the two
    # implementations, which is what the shared contract fixtures compare.
    record CommandPayload,
      name : String,
      hidden : Array(String)? = nil,
      rename_from : String? = nil,
      target : String? = nil,
      percent : Int32? = nil do
      # Writes the wire-format JSON object for this command payload.
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "name", name
          # Presence, not emptiness: an empty list is the meaningful statement
          # "this profile hides nothing" and has to travel as `[]` rather than
          # be dropped, while a command that carries no list at all omits the
          # key entirely.
          json.field "hidden", hidden if hidden
          # Left out rather than sent as `null` when there is nothing to
          # rename, so a daemon that has never heard of it still accepts every
          # payload an ordinary save produces.
          json.field "rename_from", rename_from if rename_from
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
