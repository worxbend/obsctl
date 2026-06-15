require "../config/config"

module Obsctl
  module Runtime
    class ReconnectPolicy
      def initialize(@config : Config::ReconnectConfig)
      end

      def delay_for(attempt : Int32) : Time::Span
        delay = @config.initial_delay_ms * (@config.multiplier ** attempt)
        capped = Math.min(delay, @config.max_delay_ms)
        capped.to_i.milliseconds
      end
    end
  end
end
