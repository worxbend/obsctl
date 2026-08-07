require "./ring_engine"

module CryTUI
  module Widgets
    # The outline a `RectSpinner` walks. Upstream only ships a square, so this
    # is a one-variant shape carrying its thickness; it exists so a future
    # non-square outline can be added without changing the widget's signature.
    struct RectShape
      getter size : Int32

      def initialize(size : Int32)
        @size = size.clamp(2, 8)
      end

      def self.square(size : Int32 = 2) : RectShape
        new(size)
      end
    end

    # A braille arc rotating around a rectangle outline.
    struct RectSpinner
      getter tick : UInt64
      getter shape : RectShape
      getter spin : Spin
      getter ticks_per_step : UInt64
      getter outer_color : Color
      getter inner_color : Color
      getter centre : Centre
      getter block : Block?
      getter style : Style
      getter alignment : Alignment

      def initialize(
        @tick : UInt64,
        @shape : RectShape = RectShape.square,
        @spin : Spin = Spin::Clockwise,
        ticks_per_step : UInt64 = 1_u64,
        @outer_color : Color = Color::CYAN,
        @inner_color : Color = Color::DARK_GRAY,
        @centre : Centre = Centre::Filled,
        @block : Block? = nil,
        @style : Style = Style.new,
        @alignment : Alignment = Alignment::Left,
      )
        @ticks_per_step = {ticks_per_step, 1_u64}.max
      end

      def char_size : Tuple(Int32, Int32)
        RingEngine.char_size(@shape.size)
      end

      def lines : Array(Line)
        engine = RingEngine.new(@shape.size, @centre)
        engine.advance(@tick // @ticks_per_step)
        rows = engine.lines(@outer_color, @inner_color, @alignment)
        # Mirroring each row is what reverses the walk: the arc is symmetric,
        # so a flipped clockwise frame is the counter-clockwise frame.
        return rows unless @spin.counter_clockwise?
        rows.map { |line| Line.new(line.spans.reverse, line.alignment, line.style) }
      end

      def render(area : Rect, buffer : Buffer) : Nil
        SpinnerBody.render(area, buffer, @style, @block, lines)
      end
    end

    # A braille arc rotating around a square ring.
    #
    # The same engine as `RectSpinner` with a square-shaped preset and its own
    # defaults; kept as a separate widget because a square ring is the shape
    # most callers reach for.
    struct SquareSpinner
      getter tick : UInt64
      getter size : Int32
      getter ticks_per_step : UInt64
      getter spin : Spin
      getter centre : Centre
      getter arc_color : Color
      getter dim_color : Color
      getter block : Block?
      getter style : Style
      getter alignment : Alignment

      def initialize(
        @tick : UInt64,
        size : Int32 = 2,
        ticks_per_step : UInt64 = 1_u64,
        @spin : Spin = Spin::Clockwise,
        @centre : Centre = Centre::Filled,
        @arc_color : Color = Color::WHITE,
        @dim_color : Color = Color::DARK_GRAY,
        @block : Block? = nil,
        @style : Style = Style.new,
        @alignment : Alignment = Alignment::Left,
      )
        @size = size.clamp(2, 8)
        @ticks_per_step = {ticks_per_step, 1_u64}.max
      end

      def char_size : Tuple(Int32, Int32)
        RingEngine.char_size(@size)
      end

      def lines : Array(Line)
        RectSpinner.new(
          tick: @tick,
          shape: RectShape.square(@size),
          spin: @spin,
          ticks_per_step: @ticks_per_step,
          outer_color: @arc_color,
          inner_color: @dim_color,
          centre: @centre,
          alignment: @alignment
        ).lines
      end

      def render(area : Rect, buffer : Buffer) : Nil
        SpinnerBody.render(area, buffer, @style, @block, lines)
      end
    end
  end
end
