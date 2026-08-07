module Obsctl
  module TUI
    # The level maths the audio mixer is drawn from.
    #
    # Kept out of the widget because the model records peak holds in the same
    # units the meter is scaled in, and the model must not depend on a widget.
    module Meter
      extend self

      # Everything quieter than this reads as silence. OBS' own mixer bottoms
      # out at -60 dBFS, so a channel that looks dead here looks dead there.
      FLOOR_DB = -60.0
      # OBS colours a meter green up to -20 dBFS, yellow to -9, red above it.
      WARNING_DB = -20.0
      DANGER_DB  =  -9.0
      # Close enough to full scale to call it clipping.
      CLIP_DB = -1.0

      # How much of the meter the peak marker falls per frame. At the default
      # 100 ms refresh a peak takes about two seconds to slide from the top to
      # the floor, which is slow enough to read and quick enough to keep up.
      PEAK_FALL_PER_FRAME = 0.006

      def decibels(level : Float64) : Float64
        return FLOOR_DB if level < 1e-7
        {20.0 * Math.log10(level), FLOOR_DB}.max
      end

      # Where a level sits on the meter, 0 at the floor and 1 at full scale.
      def fraction(level : Float64) : Float64
        ((decibels(level) - FLOOR_DB) / -FLOOR_DB).clamp(0.0, 1.0)
      end

      # The inverse: what a point on the meter is worth in dBFS. Used to colour
      # a cell by the level it stands for rather than by its position.
      def fraction_decibels(fraction : Float64) : Float64
        FLOOR_DB + fraction.clamp(0.0, 1.0) * -FLOOR_DB
      end
    end
  end
end
