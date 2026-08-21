require "./braille"

module CryTUI
  module Widgets
    # Which way the lit window travels along the axis.
    enum Flow
      Forwards
      Backwards
    end

    # The glyph pair a `LinearSpinner` draws lit and unlit slots with.
    enum LinearStyle
      Classic
      Square
      Diamond
      Bar
      Braille
      Arrow

      # `{lit, unlit}`. Only Arrow cares about the axis -- it points along it.
      def symbols(direction : Direction) : Tuple(String, String)
        case self
        in .classic? then {"●", "·"}
        in .square?  then {"■", "□"}
        in .diamond? then {"◆", "◇"}
        in .bar?     then {"▰", "▱"}
        in .braille? then {"⣿", "⠀"}
        in .arrow?   then direction.horizontal? ? {"▶", "▷"} : {"▼", "▽"}
        end
      end

      # Every style occupies exactly one terminal column: all the glyphs above
      # are East-Asian-Width Narrow or Ambiguous, both of which Western
      # terminals render single-width.
      def columns_per_slot : Int32
        1
      end
    end

    # A row or column of slots with a lit window moving through it.
    #
    # Horizontally the window scrolls and wraps; vertically a single lit slot
    # bounces between the ends, which reads as an activity indicator beside a
    # log or a list.
    struct LinearSpinner
      getter tick : UInt64
      getter total_slots : Int32
      getter lit_slots : Int32
      getter ticks_per_step : UInt64
      getter direction : Direction
      getter flow : Flow
      getter linear_style : LinearStyle
      getter active_color : Color
      getter inactive_color : Color
      getter block : Block?
      getter style : Style

      def initialize(
        @tick : UInt64,
        total_slots : Int32 = 3,
        lit_slots : Int32 = 2,
        ticks_per_step : UInt64 = 3_u64,
        @direction : Direction = Direction::Horizontal,
        @flow : Flow = Flow::Forwards,
        @linear_style : LinearStyle = LinearStyle::Classic,
        @active_color : Color = Color::WHITE,
        @inactive_color : Color = Color::DARK_GRAY,
        @block : Block? = nil,
        @style : Style = Style.new,
      )
        @total_slots = {total_slots, 1}.max
        @lit_slots = {lit_slots, 1}.max
        @ticks_per_step = {ticks_per_step, 1_u64}.max
      end

      def lines : Array(Line)
        @direction.horizontal? ? [horizontal_line] : vertical_lines(@total_slots)
      end

      def render(area : Rect, buffer : Buffer) : Nil
        SpinnerBody.render(area, buffer, @style, @block) do |content|
          @direction.horizontal? ? [horizontal_line] : vertical_lines(content.height)
        end
      end

      def horizontal_line : Line
        total = @total_slots
        lit = {@lit_slots, total}.min
        raw = (step % total).to_i
        # Backwards runs the index in reverse so the window scrolls right to
        # left without changing how the window itself is measured.
        start = @flow.forwards? ? raw : (total - 1) - raw
        spans = (0...total).map do |index|
          inside = if start + lit <= total
                     index >= start && index < start + lit
                   else
                     # The window straddles the end of the row.
                     index >= start || index < (start + lit) % total
                   end
          slot(inside)
        end
        Line.new(spans)
      end

      def vertical_lines(height : Int32) : Array(Line)
        count = @total_slots
        active = bounce_index
        lines = Array.new({height, 0}.max) { Line.new }
        return lines if lines.empty?
        # The slots are pinned to the bottom of the area so the indicator sits
        # next to the newest row when it runs beside a log.
        start = height >= count ? height - count : 0
        (start...height).each_with_index do |row, index|
          lines[row] = Line.new([slot(index == active)])
        end
        lines
      end

      def bounce_index : Int32
        count = @total_slots
        return 0 if count == 1
        cycle = 2 * (count - 1)
        position = (step % cycle).to_i
        index = position < count ? position : cycle - position
        @flow.forwards? ? index : (count - 1) - index
      end

      private def step : UInt64
        @tick // @ticks_per_step
      end

      private def slot(lit : Bool) : Span
        on, off = @linear_style.symbols(@direction)
        if lit
          Span.new(on, Style.new(foreground: @active_color, modifiers: Modifier::Bold))
        else
          Span.new(off, Style.new(foreground: @inactive_color))
        end
      end
    end
  end
end
