require "./braille"

module CryTUI
  module Widgets
    # Frame sequences for `FluxSpinner`.
    #
    # Every preset is a plain `Array(String)`, so a caller can pass one of these
    # or any sequence of its own.
    module FluxFrames
      # Full braille cell with one dot missing -- the gap rotates clockwise.
      BRAILLE = %w[⣾ ⣷ ⣯ ⣟ ⡿ ⢿ ⣽ ⣻]
      # A single braille dot orbiting clockwise; the visual complement of BRAILLE.
      ORBIT = %w[⠁ ⠈ ⠐ ⠠ ⢀ ⡀ ⠄ ⠂]
      # The classic ten-frame braille spinner.
      CLASSIC = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
      # Rotating line.
      LINE = %w[│ ╱ ─ ╲]
      # Quarter-block rotation.
      BLOCK = %w[▖ ▘ ▝ ▗]
      # Quarter-arc rotation.
      ARC = %w[◜ ◝ ◞ ◟]
      # Quarter-circle pie slice.
      CLOCK = %w[◷ ◶ ◵ ◴]
      # Half-circle moon phase.
      MOON = %w[◓ ◑ ◒ ◐]
      # Filled triangle pointing in four directions.
      TRIANGLES = %w[▲ ▶ ▼ ◀]
      # Braille fill pulsing up to full density and back.
      PULSE = %w[⣀ ⣤ ⣶ ⣾ ⣿ ⣾ ⣶ ⣤]
      # A braille row bouncing top to bottom. `⠒` repeats -- that is the return step.
      BOUNCE = %w[⠉ ⠒ ⣀ ⠒]
      # Half-block rotating clockwise.
      HALF = %w[▀ ▐ ▄ ▌]
      # White square with one filled quadrant rotating clockwise.
      SQUARE = %w[◰ ◳ ◲ ◱]
      # Dice faces one through six.
      DICE = %w[⚀ ⚁ ⚂ ⚃ ⚄ ⚅]
      # Sub-block glyphs growing from one eighth to full height.
      BAR = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █]
      # Box-drawing corners rotating clockwise.
      CORNERS = %w[┌ ┐ ┘ └]
      # A circle filling clockwise in five stages.
      CIRCLE_FILL = %w[○ ◔ ◑ ◕ ●]
      # A bar bouncing to full height and back; the middle glyphs repeat.
      PISTON = %w[▁ ▃ ▅ ▇ █ ▇ ▅ ▃]
      # Four star glyphs increasing in density.
      STAR = %w[✶ ✷ ✸ ✹]
      # Two adjacent braille dots rotating around the cell.
      PAIR = %w[⠉ ⠘ ⠰ ⢠ ⣀ ⡄ ⠆ ⠃]
      # Diamond pulsing hollow to solid; `◈` repeats on the way back.
      DIAMOND = %w[◇ ◈ ◆ ◈]

      # Every preset, in declaration order, paired with its name -- what a
      # gallery or a settings picker enumerates.
      ALL = {
        "braille"     => BRAILLE,
        "orbit"       => ORBIT,
        "classic"     => CLASSIC,
        "line"        => LINE,
        "block"       => BLOCK,
        "arc"         => ARC,
        "clock"       => CLOCK,
        "moon"        => MOON,
        "triangles"   => TRIANGLES,
        "pulse"       => PULSE,
        "bounce"      => BOUNCE,
        "half"        => HALF,
        "square"      => SQUARE,
        "dice"        => DICE,
        "bar"         => BAR,
        "corners"     => CORNERS,
        "circle-fill" => CIRCLE_FILL,
        "piston"      => PISTON,
        "star"        => STAR,
        "pair"        => PAIR,
        "diamond"     => DIAMOND,
      }

      def self.by_name(name : String) : Array(String)?
        ALL[name.downcase]?
      end
    end

    # A glyph cycling through a frame sequence.
    #
    # At 1x1 this is a single animated character -- the compact status-bar
    # spinner. Widen or heighten it and each cell is offset from its neighbour
    # by `phase_step` frames, which turns the sequence into a wave travelling
    # in the spin direction.
    struct FluxSpinner
      getter tick : UInt64
      getter width : Int32
      getter height : Int32
      getter spin : Spin
      getter color : Color
      getter ticks_per_step : UInt64
      getter phase_step : Int32
      getter frames : Array(String)
      getter block : Block?
      getter style : Style
      getter alignment : Alignment

      def initialize(
        @tick : UInt64,
        width : Int32 = 1,
        height : Int32 = 1,
        @spin : Spin = Spin::Clockwise,
        @color : Color = Color::CYAN,
        ticks_per_step : UInt64 = 1_u64,
        phase_step : Int32 = 1,
        @frames : Array(String) = FluxFrames::BRAILLE,
        @block : Block? = nil,
        @style : Style = Style.new,
        @alignment : Alignment = Alignment::Left,
      )
        @width = {width, 1}.max
        @height = {height, 1}.max
        @ticks_per_step = {ticks_per_step, 1_u64}.max
        @phase_step = {phase_step, 0}.max
      end

      # The glyph a single-cell spinner is showing, for callers that only want
      # to splice one character into a line of their own.
      def glyph : String
        return "" if @frames.empty?
        @frames[frame_index(0)]
      end

      def lines : Array(Line)
        return [] of Line if @frames.empty?
        (0...@height).map do |row|
          spans = (0...@width).map do |col|
            Span.new(@frames[frame_index(row * @width + col)], Style.new(foreground: @color))
          end
          Line.new(spans, @alignment)
        end
      end

      def char_size : Tuple(Int32, Int32)
        {@width, @height}
      end

      def render(area : Rect, buffer : Buffer) : Nil
        SpinnerBody.render(area, buffer, @style, @block, lines)
      end

      private def frame_index(cell : Int32) : Int32
        count = @frames.size
        # Every cell shares one base step and adds its own phase offset, which
        # is what staggers neighbours into a wave instead of a uniform pulse.
        raw = ((@tick // @ticks_per_step) + (cell.to_u64 * @phase_step.to_u64)) % count
        @spin.counter_clockwise? ? (count - raw.to_i) % count : raw.to_i
      end
    end
  end
end
