require "../../state/obs_snapshot"
require "../meter"
require "./anim_clock"

module Obsctl
  module TUI
    # The meters and the sparklines: what the dashboard measures over time
    # rather than what the daemon reported at an instant.
    #
    # The clock is passed in rather than held, so every answer here stays a
    # pure function of the readings and the frame they are asked at -- the
    # peak marker falls with the clock, not with a timer somebody has to run
    # between renders.
    class StatsPaneState
      # How many samples each sparkline keeps. The stats widgets plot these at
      # one column per sample, so this is also the widest a sparkline can be
      # before it starts repeating; 32 covers the panel at any usable terminal
      # width without holding history nothing draws.
      METRIC_HISTORY_SAMPLES = 32

      getter meter_levels : Hash(String, Float64)
      # The highest point each meter has reached and the frame it reached it
      # on. Storing the frame rather than decaying the value every tick keeps
      # the peak marker a pure function of the clock, so nothing has to run
      # between renders for it to fall.
      @meter_peaks : Hash(String, Tuple(Float64, UInt64))
      property cpu_history : Array(Float64)
      property bitrate_history : Array(Float64)
      property fps_history : Array(Float64)

      def initialize
        @meter_levels = {} of String => Float64
        @meter_peaks = {} of String => Tuple(Float64, UInt64)
        @cpu_history = [] of Float64
        @bitrate_history = [] of Float64
        @fps_history = [] of Float64
      end

      # Appends this frame's readings to the sparkline histories.
      #
      # Each series is sampled only when the snapshot actually carries it: a
      # snapshot with no stats must not push a zero, because a zero is a real
      # reading that would draw as a trough in the graph rather than as the
      # absence of data it really is.
      def record_sample(stats : State::ObsStats?, bitrate_kbps : Float64?) : Nil
        if current_stats = stats
          append_metric(@cpu_history, current_stats.cpu_usage_percent)
          append_metric(@fps_history, current_stats.active_fps)
        end
        if bitrate = bitrate_kbps
          append_metric(@bitrate_history, bitrate)
        end
      end

      # Adds one reading and drops whatever has scrolled off the left edge.
      #
      # The trim lives here rather than in `record_sample` so the bound holds
      # for every series by construction; it used to be a separate pass over
      # all three arrays afterwards, which is a rule that only holds as long
      # as someone remembers to add the next series to that list.
      private def append_metric(history : Array(Float64), value : Float64) : Nil
        history << value
        history.shift(history.size - METRIC_HISTORY_SAMPLES) if history.size > METRIC_HISTORY_SAMPLES
      end

      # Records a meter reading and raises the peak hold when the reading beats
      # whatever is left of the last one.
      def record_meter_level(input_name : String, level : Float64, clock : AnimClock) : Nil
        @meter_levels[input_name] = level
        fraction = Meter.fraction(level)
        held = meter_peak(input_name, clock)
        @meter_peaks[input_name] = {fraction, clock.frame} if held.nil? || fraction >= held
      end

      # How far up the meter the peak marker has fallen to by now, or nil once
      # it has slid all the way back to the floor.
      def meter_peak(input_name : String, clock : AnimClock) : Float64?
        peak = @meter_peaks[input_name]?
        return unless peak
        remaining = peak[0] - (clock.frame - peak[1]).to_f64 * Meter::PEAK_FALL_PER_FRAME
        remaining > 0.0 ? remaining : nil
      end
    end
  end
end
