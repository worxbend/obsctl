require "json"

module Obsctl
  module Server
    # The one place that builds a `logs` topic entry.
    #
    # Three producers publish into the same topic — the supervisor (OBS
    # connection lifecycle), the command executor (per-command failures), and
    # the server itself (daemon lifecycle) — and every subscriber, the TUI log
    # panel and `obsctl watch` alike, parses the result. The field set is
    # public contract (see `docs/protocol.md`), so it is built here rather than
    # spelled out three times where one of the three could drift.
    module LogPayload
      # Builds one log entry: severity, stable machine-readable code, human
      # message, and the moment it happened.
      def self.build(level : String, code : String, message : String, at : Time = Time.utc) : JSON::Any
        JSON.parse({
          level:      level,
          code:       code,
          message:    message,
          created_at: at.to_rfc3339,
        }.to_json)
      end
    end
  end
end
