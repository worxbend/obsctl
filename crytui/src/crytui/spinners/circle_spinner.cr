require "./braille"

module CryTUI
  module Widgets
    # A braille dot ring with an arc rotating around it.
    #
    # The ring is a midpoint-circle perimeter sorted by angle, so the arc is a
    # contiguous run of that list and rotating it is a single index step. The
    # unlit remainder of the ring stays visible in `dim_color`, which is what
    # separates this from a bare chasing dot.
    struct CircleSpinner
      getter tick : UInt64
      getter radius : Int32
      getter arc_len : Int32
      getter ticks_per_step : UInt64
      getter spin : Spin
      getter arc_color : Color
      getter dim_color : Color
      getter block : Block?
      getter style : Style
      getter alignment : Alignment

      def initialize(
        @tick : UInt64,
        radius : Int32 = 4,
        arc_len : Int32 = 0,
        ticks_per_step : UInt64 = 1_u64,
        @spin : Spin = Spin::Clockwise,
        @arc_color : Color = Color::WHITE,
        @dim_color : Color = Color::DARK_GRAY,
        @block : Block? = nil,
        @style : Style = Style.new,
        @alignment : Alignment = Alignment::Left,
      )
        @radius = {radius, 1}.max
        @arc_len = {arc_len, 0}.max
        @ticks_per_step = {ticks_per_step, 1_u64}.max
      end

      def char_size : Tuple(Int32, Int32)
        span = @radius * 2 + 1
        {(span + 1) // 2, (span + 3) // 4}
      end

      def lines : Array(Line)
        perimeter = CircleSpinner.perimeter(@radius)
        count = perimeter.size
        arc = @arc_len > 0 ? {@arc_len, count}.min : {count // 4, 1}.max
        # The whole animation is one index walking a ring, so a tick of any age
        # folds into a single revolution.
        steps = ((@tick // @ticks_per_step) % count).to_i
        tail = if @spin.counter_clockwise?
                 (arc - steps + count) % count
               else
                 (count - arc + steps) % count
               end
        pack_lines(perimeter, arc, tail)
      end

      def render(area : Rect, buffer : Buffer) : Nil
        SpinnerBody.render(area, buffer, @style, @block, lines)
      end

      # Midpoint circle, reflected through all eight octants and then sorted
      # clockwise from the top so index order is travel order.
      def self.perimeter(radius : Int32) : Array(RingCoord)
        return [RingCoord.new(0, 0)] if radius <= 0

        points = Set(Tuple(Int32, Int32)).new
        x = 0
        y = radius
        d = 1 - radius
        while x <= y
          { {x, -y}, {y, -x}, {y, x}, {x, y}, {-x, y}, {-y, x}, {-y, -x}, {-x, -y} }.each do |point|
            points << {point[1], point[0]}
          end
          if d < 0
            d += 2 * x + 3
          else
            d += 2 * (x - y) + 5
            y -= 1
          end
          x += 1
        end
        sort_clockwise(points.to_a)
      end

      private def self.sort_clockwise(dots : Array(Tuple(Int32, Int32))) : Array(RingCoord)
        return [] of RingCoord if dots.empty?
        count = dots.size.to_f64
        centre_row = dots.sum(&.[0].to_f64) / count
        centre_col = dots.sum(&.[1].to_f64) / count
        dots.sort_by do |dot|
          # atan2 of (east, north) puts zero at the top and grows clockwise.
          angle = Math.atan2(dot[1] - centre_col, -(dot[0] - centre_row))
          angle < 0 ? angle + 2 * Math::PI : angle
        end.map { |dot| RingCoord.new(dot[0], dot[1]) }
      end

      # Packs the ring into braille cells, lighting the arc run in `arc_color`
      # and everything else in `dim_color`.
      private def pack_lines(perimeter : Array(RingCoord), arc : Int32, tail : Int32) : Array(Line)
        count = perimeter.size
        min_row = perimeter.min_of(&.row)
        min_col = perimeter.min_of(&.col)
        dot_rows = perimeter.max_of(&.row) - min_row + 1
        dot_cols = perimeter.max_of(&.col) - min_col + 1
        char_rows = (dot_rows + 3) // 4
        char_cols = (dot_cols + 1) // 2

        lit = Set(RingCoord).new
        arc.times { |offset| lit << perimeter[(tail + offset) % count] }

        bright = Array.new(char_rows) { Array.new(char_cols, 0_u8) }
        dim = Array.new(char_rows) { Array.new(char_cols, 0_u8) }
        perimeter.each do |dot|
          row = dot.row - min_row
          col = dot.col - min_col
          bit = 1_u8 << Braille::MAP[row % 4][col % 2]
          target = lit.includes?(dot) ? bright : dim
          target[row // 4][col // 2] |= bit
        end

        (0...char_rows).map do |row|
          spans = (0...char_cols).map do |col|
            byte = bright[row][col]
            color = @arc_color
            if byte == 0
              byte = dim[row][col]
              color = @dim_color
            end
            Span.new(Braille.char(byte), Style.new(foreground: color))
          end
          Line.new(spans, @alignment)
        end
      end
    end
  end
end
