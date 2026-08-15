require "../config/config"

module Obsctl
  module Runtime
    # Computes bounded exponential reconnect delays from config.
    class ReconnectPolicy
      # Shortest delay this policy will ever return.
      #
      # `reconnect.initial_delay_ms: 0` is a legal config, and combined with
      # `max_delay_ms: 0` it used to produce a zero-length wait — the supervisor
      # would retry as fast as the scheduler allowed, burning a core and
      # hammering the OBS port. A user asking for zero means "retry as soon as
      # possible", not "spin", so the wait is floored here rather than the
      # config being rejected, which would break anyone already using zero.
      MINIMUM_DELAY = 50.milliseconds

      # Creates a reconnect policy view over the configured reconnect settings.
      #
      # `random` is injectable so specs can assert the jitter range without
      # depending on a particular sequence of random numbers.
      def initialize(@config : Config::ReconnectConfig, @random : Random = Random.new)
      end

      # Returns the delay for a zero-based reconnect attempt.
      def delay_for(attempt : Int32) : Time::Span
        delay = @config.initial_delay_ms * (@config.multiplier ** attempt)
        capped = Math.min(delay, @config.max_delay_ms)
        span = capped.to_i.milliseconds + jitter
        span < MINIMUM_DELAY ? MINIMUM_DELAY : span
      end

      # Returns a random offset in `0...jitter_ms`, added on top of the capped
      # delay.
      #
      # Without it every obsctl instance retries on the identical schedule
      # (500ms, 900ms, 1620ms, ...), so a machine running several of them —
      # or a set of machines restarted together — reconnects in lockstep and
      # arrives at OBS as one burst each time. Spreading the attempts is the
      # entire point of the documented `reconnect.jitter_ms` setting.
      private def jitter : Time::Span
        jitter_ms = @config.jitter_ms
        return 0.milliseconds if jitter_ms <= 0

        @random.rand(jitter_ms).milliseconds
      end
    end
  end
end
