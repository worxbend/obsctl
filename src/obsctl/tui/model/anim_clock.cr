module Obsctl
  module TUI
    struct AnimClock
      property frame : UInt64

      def initialize(@frame = 0_u64)
      end

      def tick
        @frame &+= 1
      end

      def pulse(period_ticks : UInt64) : Float32
        period = {period_ticks, 1_u64}.max
        phase = (@frame % period).to_f32 / period.to_f32
        Math.sin(phase * Math::TAU.to_f32) * 0.5_f32 + 0.5_f32
      end

      def spinner(frames : Indexable(String), ticks_per_frame : UInt64 = 1_u64) : String
        return "" if frames.empty?
        step = {ticks_per_frame, 1_u64}.max
        frames[((@frame // step) % frames.size).to_i]
      end
    end
  end
end
