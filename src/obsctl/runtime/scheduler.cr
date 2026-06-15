module Obsctl
  module Runtime
    # Minimal periodic task scheduler used by runtime components.
    class Scheduler
      # Runs the given block forever at the requested interval in a fiber.
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
