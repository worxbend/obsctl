require "../config/config"

module Obsctl
  module Runtime
    # Computes bounded exponential reconnect delays from config.
    class ReconnectPolicy
      # Creates a reconnect policy view over the configured reconnect settings.
      def initialize(@config : Config::ReconnectConfig)
      end

      # Returns the delay for a zero-based reconnect attempt.
      def delay_for(attempt : Int32) : Time::Span
        delay = @config.initial_delay_ms * (@config.multiplier ** attempt)
        capped = Math.min(delay, @config.max_delay_ms)
        capped.to_i.milliseconds
      end
    end
  end
end
