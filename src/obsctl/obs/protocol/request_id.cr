module Obsctl
  module OBS
    module Protocol
      class RequestId
        @counter = Atomic(Int64).new(0)

        def next : String
          "obsctl-#{@counter.add(1)}"
        end
      end
    end
  end
end
