module Obsctl
  module OBS
    module Protocol
      # Generates unique request IDs for obs-websocket request correlation.
      class RequestId
        @counter = Atomic(Int64).new(0)

        # Returns the next local request ID.
        def next : String
          "obsctl-#{@counter.add(1)}"
        end
      end
    end
  end
end
