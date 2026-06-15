module Obsctl
  module Runtime
    class EventLoop
      def initialize(@stop = Channel(Nil).new)
      end

      def stop : Nil
        @stop.send(nil)
      end

      def run : Nil
        @stop.receive
      end
    end
  end
end
