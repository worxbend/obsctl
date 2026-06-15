module Obsctl
  module Runtime
    # Tiny blocking loop that can be stopped through an internal channel.
    class EventLoop
      # Creates an event loop using an optional external stop channel.
      def initialize(@stop = Channel(Nil).new)
      end

      # Requests that the event loop return.
      def stop : Nil
        @stop.send(nil)
      end

      # Blocks until `#stop` is called.
      def run : Nil
        @stop.receive
      end
    end
  end
end
