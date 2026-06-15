module Obsctl
  module Runtime
    class Scheduler
      def every(interval : Time::Span, &) : Fiber
        spawn do
          loop do
            yield
            sleep interval
          end
        end
      end
    end
  end
end
