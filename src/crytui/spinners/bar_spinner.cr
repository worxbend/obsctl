require "./braille"

module CryTUI
  module Widgets
    # The glyph the unlit part of a bar is drawn with, as a braille byte.
    struct BarTrack
      getter byte : UInt8

      def initialize(@byte : UInt8)
      end

      # A thin centre line, so the bar reads as a track the glow runs along.
      RAIL = new(0xC0_u8)
      # Every dot lit -- a solid bar the glow brightens rather than fills.
      FULL = new(0xFF_u8)
      # Nothing at all, for a glow travelling over empty space.
      EMPTY = new(0x00_u8)

      def self.custom(byte : UInt8) : BarTrack
        new(byte)
      end
    end

    # The symbol pair a bar is drawn with. `Braille` is the only one that uses
    # sub-cell dots, and so the only one the fade gradient applies to.
    enum BarStyle
      Braille
      Block
      Shade
      Dot
      Diamond
      Square
      Star
      Heart
      Arrow
      Circle
      Spark
      Cross
      Progress
      Thick
      Wave
      Pip

      # `{lit, unlit}`, or nil for Braille, which is rendered from dot bytes.
      def chars : Tuple(String, String)?
        case self
        in .braille?  then nil
        in .block?    then {"█", "░"}
        in .shade?    then {"▓", "░"}
        in .dot?      then {"●", "·"}
        in .diamond?  then {"◆", "◇"}
        in .square?   then {"■", "□"}
        in .star?     then {"★", "☆"}
        in .heart?    then {"♥", "♡"}
        in .arrow?    then {"▶", "▷"}
        in .circle?   then {"◉", "○"}
        in .spark?    then {"✦", "✧"}
        in .cross?    then {"✚", "✛"}
        in .progress? then {"▰", "▱"}
        in .thick?    then {"━", "─"}
        in .wave?     then {"≈", "˜"}
        in .pip?      then {"▪", "·"}
        end
      end
    end

    # How the lit arc moves along the bar.
    enum BarMotion
      # One arc ping-ponging between the ends.
      Bounce
      # One arc travelling in one direction and wrapping around.
      Loop
      # Two arcs converging on the centre and separating again.
      Squeeze
      # Two arcs starting at the centre and running out to the edges.
      Radiate
    end

    # The motion of a bar, independent of which axis it is drawn on.
    #
    # `length` is columns for a horizontal bar and rows for a vertical one; the
    # anchor walk and the arc test are identical either way, which is why one
    # engine serves both orientations.
    class BarEngine
      # Braille bytes for a quarter, half, three-quarter and full-height dot
      # column: the gradient that softens an arc's leading and trailing edge.
      FADE = [0x09_u8, 0x1B_u8, 0x3F_u8, 0xFF_u8]

      getter length : Int32
      getter arc : Int32
      getter anchor : Int32
      getter? going_forward : Bool
      getter motion : BarMotion

      def initialize(@length : Int32, @arc : Int32, spin : Spin, @motion : BarMotion)
        # Squeeze and radiate are symmetric, so they always start from their
        # zero phase -- arcs at the edges and at the centre respectively -- and
        # ignore the spin direction.
        @going_forward = (@motion.squeeze? || @motion.radiate?) ? true : spin.clockwise?
        @anchor = if @motion.squeeze? || @motion.radiate?
                    0
                  elsif @going_forward
                    0
                  else
                    {@length - @arc, 0}.max
                  end
      end

      # Replays `steps` walks. The engine's whole state is the anchor and its
      # direction, so a tick of any age folds into one period.
      def advance(steps : UInt64) : Nil
        (steps % period.to_u64).times { walk }
      end

      # Bounce and squeeze spend one extra step at each end flipping direction
      # rather than moving, which is where the `+ 1` comes from.
      def period : Int32
        case @motion
        in .bounce?  then 2 * ({@length - @arc, 0}.max + 1)
        in .loop?    then {@length, 1}.max
        in .squeeze? then 2 * (({@length - @arc, 0}.max // 2) + 1)
        in .radiate? then ({@length - @arc, 0}.max // 2) + 1
        end
      end

      def walk : Nil
        case @motion
        in .bounce?
          swing({@length - @arc, 0}.max)
        in .loop?
          @anchor = @going_forward ? (@anchor + 1) % @length : (@anchor + @length - 1) % @length
        in .squeeze?
          swing({@length - @arc, 0}.max // 2)
        in .radiate?
          @anchor = (@anchor + 1) % (({@length - @arc, 0}.max // 2) + 1)
        end
      end

      # Whether `index` is inside the lit arc, and how far it is from the
      # nearer end of it -- the distance the fade gradient is drawn from.
      def slot(index : Int32) : Tuple(Bool, Int32)
        case @motion
        in .bounce?
          within(index, @anchor, @anchor + @arc)
        in .loop?
          offset = (index + @length - @anchor) % @length
          offset < @arc ? {true, {offset, @arc - 1 - offset}.min} : {false, 0}
        in .squeeze?
          right_end = {@length - @anchor, 0}.max
          hit = within(index, @anchor, @anchor + @arc)
          hit[0] ? hit : within(index, {right_end - @arc, 0}.max, right_end)
        in .radiate?
          centre = @length // 2
          right_start = centre + @anchor
          hit = within(index, right_start, {right_start + @arc, @length}.min)
          return hit if hit[0]
          left_end = {centre - @anchor, 0}.max
          within(index, {left_end - @arc, 0}.max, left_end)
        end
      end

      def self.fade_byte(from_edge : Int32, fade_width : Int32, arc_byte : UInt8) : UInt8
        return arc_byte if fade_width <= 0 || from_edge >= fade_width
        FADE[{(from_edge * 3 + fade_width - 1) // fade_width, 2}.min]
      end

      # Walks the anchor up to `limit` and back, pausing a step at each end.
      private def swing(limit : Int32) : Nil
        if @going_forward
          if @anchor < limit
            @anchor += 1
          else
            @going_forward = false
          end
        elsif @anchor > 0
          @anchor -= 1
        else
          @going_forward = true
        end
      end

      private def within(index : Int32, start : Int32, finish : Int32) : Tuple(Bool, Int32)
        return {false, 0} unless index >= start && index < finish
        {true, {index - start, finish - 1 - index}.min}
      end
    end

    # A bar with a glow running along it.
    #
    # Left to itself it fills whatever width it is given, which makes it the
    # spinner to reach for when the indicator should span a panel rather than
    # sit in a corner.
    struct BarSpinner
      getter tick : UInt64
      getter width : Int32
      getter height : Int32
      getter arc_width : Int32
      getter spin : Spin
      getter ticks_per_step : UInt64
      getter arc_color : Color
      getter dim_color : Color
      getter track : BarTrack
      getter fade_width : Int32
      getter arc_byte : UInt8
      getter bar_style : BarStyle
      getter motion : BarMotion
      getter orientation : Direction
      getter thickness : Int32
      getter block : Block?
      getter style : Style
      getter alignment : Alignment

      def initialize(
        @tick : UInt64,
        @width : Int32 = 0,
        height : Int32 = 1,
        @arc_width : Int32 = 0,
        @spin : Spin = Spin::Clockwise,
        ticks_per_step : UInt64 = 1_u64,
        @arc_color : Color = Color::CYAN,
        @dim_color : Color = Color::DARK_GRAY,
        @track : BarTrack = BarTrack::RAIL,
        @fade_width : Int32 = 3,
        @arc_byte : UInt8 = 0xFF_u8,
        @bar_style : BarStyle = BarStyle::Braille,
        @motion : BarMotion = BarMotion::Bounce,
        @orientation : Direction = Direction::Horizontal,
        @thickness : Int32 = 0,
        @block : Block? = nil,
        @style : Style = Style.new,
        @alignment : Alignment = Alignment::Left,
      )
        @height = {height, 1}.max
        @ticks_per_step = {ticks_per_step, 1_u64}.max
      end

      # The upstream presets, renamed to describe the look rather than the
      # editor each was lifted from.
      def self.slim(tick : UInt64) : BarSpinner
        new(tick, height: 1, arc_color: Color::CYAN, dim_color: Color::DARK_GRAY)
      end

      def self.ember(tick : UInt64) : BarSpinner
        new(tick, height: 2, arc_color: Color.rgb(255, 165, 0), dim_color: Color::DARK_GRAY)
      end

      def self.minimal(tick : UInt64) : BarSpinner
        new(tick, height: 1, arc_color: Color::WHITE, dim_color: Color::BLACK, track: BarTrack::EMPTY)
      end

      def self.solid(tick : UInt64) : BarSpinner
        new(tick, height: 1, arc_color: Color::CYAN, dim_color: Color::DARK_GRAY, track: BarTrack::FULL, fade_width: 0)
      end

      # `nil` when the bar has no fixed width and takes the area it is given.
      def char_size : Tuple(Int32, Int32)?
        return if @width == 0
        { {@width, 3}.max, @height }
      end

      def lines(width : Int32, height : Int32 = 1) : Array(Line)
        @orientation.horizontal? ? horizontal_lines(width) : vertical_lines(width, height)
      end

      def render(area : Rect, buffer : Buffer) : Nil
        return if area.empty?
        buffer.set_style(area, @style)
        content = area
        if block = @block
          block.render(area, buffer)
          content = block.inner(area)
        end
        return if content.empty?
        rows = lines(@width == 0 ? content.width : @width, content.height)
        rows.first(content.height).each_with_index do |line, index|
          line.render(buffer, Rect.new(content.x, content.y + index, content.width, 1), @style)
        end
      end

      private def horizontal_lines(width : Int32) : Array(Line)
        length = {width, 3}.max
        rows = @thickness > 0 ? @thickness : @height
        # Graduated dots stack into a ragged diagonal edge once a bar is more
        # than one row tall, so multi-row bars drop the gradient.
        fade = rows > 1 ? 0 : @fade_width
        engine = build(length, @arc_width > 0 ? {@arc_width, {length - 1, 1}.max}.min : {(length + 2) // 3, 4}.max)
        symbols = @bar_style.chars
        spans = (0...length).map do |index|
          inside, from_edge = engine.slot(index)
          span(inside, from_edge, fade, symbols)
        end
        Array.new({rows, 1}.max) { Line.new(spans, @alignment) }
      end

      private def vertical_lines(width : Int32, height : Int32) : Array(Line)
        columns = if @thickness > 0
                    @thickness
                  elsif @width == 0
                    width
                  else
                    @width
                  end
        columns = {columns, 1}.max
        length = {height, 3}.max
        engine = build(length, @arc_width > 0 ? {@arc_width, {length - 1, 1}.max}.min : {(length + 2) // 3, 2}.max)
        symbols = @bar_style.chars
        (0...length).map do |row|
          inside, _ = engine.slot(row)
          # A vertical bar has no room for a gradient across its thickness, so
          # every cell in a row is the same glyph.
          cell = span(inside, 0, 0, symbols)
          Line.new(Array.new(columns) { cell }, @alignment)
        end
      end

      private def build(length : Int32, arc : Int32) : BarEngine
        engine = BarEngine.new(length, arc, @spin, @motion)
        engine.advance(@tick // @ticks_per_step)
        engine
      end

      private def span(inside : Bool, from_edge : Int32, fade : Int32, symbols : Tuple(String, String)?) : Span
        if symbols
          inside ? Span.new(symbols[0], Style.new(foreground: @arc_color)) : Span.new(symbols[1], Style.new(foreground: @dim_color))
        elsif inside
          Span.new(Braille.char(BarEngine.fade_byte(from_edge, fade, @arc_byte)), Style.new(foreground: @arc_color))
        else
          Span.new(Braille.char(@track.byte), Style.new(foreground: @dim_color))
        end
      end
    end
  end
end
