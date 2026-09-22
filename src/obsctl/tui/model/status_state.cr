require "./anim_clock"

module Obsctl
  module TUI
    # What the chrome says about the dashboard itself: whether the daemon
    # socket is up, and the one-line result of the last command.
    class StatusState
      property last_result : String?
      getter last_result_frame : UInt64
      property connected_to_daemon : Bool

      def initialize
        @last_result = nil
        @last_result_frame = 0_u64
        @connected_to_daemon = false
      end

      # Stamped with the frame it was set on, so `revealed_last_result` can
      # type the line out grapheme by grapheme against the render clock
      # without a timer of its own.
      def set_last_result(message : String, clock : AnimClock) : Nil
        @last_result = message
        @last_result_frame = clock.frame
      end

      def revealed_last_result(clock : AnimClock, characters_per_frame : Int32) : String?
        result = @last_result
        return unless result
        elapsed = (clock.frame - @last_result_frame).to_i64
        result.each_grapheme.first(elapsed * characters_per_frame.clamp(1, Int32::MAX)).join
      end
    end
  end
end
