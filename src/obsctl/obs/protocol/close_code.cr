module Obsctl
  module OBS
    module Protocol
      # What a WebSocket close code means when the peer is OBS.
      #
      # Two vocabularies land in one table. Codes 1000-1013 are the WebSocket
      # standard's; codes 4000-4009 are obs-websocket 5.x's own, and their
      # meanings ("Identify was sent twice", "the requested RPC version is not
      # supported") are pure vendor protocol. Naming them is therefore the same
      # job `obs_event.cr` describes for the event stream — keep everything
      # peculiar to the vendor in `obs/protocol/` and nowhere else — so the
      # table lives here rather than inside `Transport`, whose subject is
      # sockets, framing and request correlation.
      #
      # This file requires nothing, which is the point: reaching a close code
      # through `Transport` needs a real disconnect, and a disconnect delivers
      # one code per test. As a plain function the whole table is reachable
      # from `spec/obsctl/obs/protocol/close_code_spec.cr` with no socket.
      module CloseCode
        # Returns the phrase obsctl uses for `code`, or a neutral fallback for
        # a code it does not recognize.
        def self.explanation(code : Int32) : String
          case code
          when 1000 then "normal closure requested by OBS"
          when 1001 then "OBS is going away or shutting down"
          when 1002 then "WebSocket protocol error"
          when 1005 then "OBS closed without a close status"
          when 1006 then "connection ended without a close frame"
          when 1011 then "OBS encountered an internal error"
          when 1012 then "OBS is restarting"
          when 1013 then "OBS asked the client to retry later"
          when 4000 then "OBS reported an unknown reason"
          when 4001 then "OBS could not decode a client message"
          when 4002 then "OBS received an unknown message type"
          when 4003 then "client sent a request before Identify completed"
          when 4004 then "client attempted to Identify more than once"
          when 4005 then "OBS authentication failed"
          when 4006 then "OBS does not support the requested RPC version"
          when 4007 then "OBS invalidated the session"
          when 4008 then "OBS does not support a requested feature"
          when 4009 then "an OBS request was missing its request type"
          else           "peer closed the WebSocket"
          end
        end
      end
    end
  end
end
