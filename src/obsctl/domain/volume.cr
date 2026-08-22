module Obsctl
  module Domain
    # Conversions between the two ways a volume level is spelled: the 0-100
    # percentage obsctl shows and accepts, and the multiplier obs-websocket
    # speaks.
    #
    # This lives apart from `Aliases` because it shares nothing with target
    # resolution — no types, no data, no vocabulary. Keeping it there made
    # every file that needed the arithmetic require the alias resolver, which
    # read as if that file resolved aliases when it did not.
    module Volume
      # Converts user-facing 0-100 volume to obs-websocket multiplier form.
      def self.percent_to_mul(percent : Int32) : Float64
        percent.to_f64 / 100.0
      end

      # Converts an obs-websocket multiplier back to the user-facing 0-100
      # scale, which is the only volume obsctl ever shows or accepts.
      #
      # Clamped because the multiplier is not bounded at 1.0: OBS allows gain
      # above unity, and a slider pushed past it would otherwise render as a
      # percentage over 100 that no obsctl command could ask for.
      def self.mul_to_percent(mul : Float64) : Int32
        (mul * 100).round.to_i32.clamp(0, 100)
      end
    end
  end
end
