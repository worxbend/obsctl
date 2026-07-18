module CryTUI
  module Widgets
    enum Borders
      None
      All
    end

    struct Block
      getter title : String?
      getter borders : Borders
      getter style : Style
      getter border_style : Style

      def initialize(@title = nil, @borders = Borders::All, @style = Style.new, @border_style = Style.new)
      end

      def inner(area : Rect) : Rect
        @borders.all? ? area.inner(1) : area
      end

      def render(area : Rect, buffer : Buffer)
        return if area.empty?
        buffer.set_style(area, @style)
        return unless @borders.all?
        left, right, top, bottom = area.left, area.right - 1, area.top, area.bottom - 1
        (left..right).each do |x|
          buffer.set_string(x, top, x == left || x == right ? "+" : "-", @border_style)
          buffer.set_string(x, bottom, x == left || x == right ? "+" : "-", @border_style) if bottom != top
        end
        (top + 1...bottom).each do |y|
          buffer.set_string(left, y, "|", @border_style)
          buffer.set_string(right, y, "|", @border_style) if right != left
        end
        buffer.set_string(left + 2, top, " #{@title} ", @border_style, area.width - 4) if @title && area.width >= 4
      end
    end

    struct Paragraph
      getter text : String
      getter style : Style
      getter block : Block?

      def initialize(@text, @style = Style.new, @block = nil)
      end

      def render(area : Rect, buffer : Buffer)
        content = area
        if block = @block
          block.render(area, buffer)
          content = block.inner(area)
        end
        @text.lines.first(content.height).each_with_index do |line, index|
          buffer.set_string(content.x, content.y + index, line, @style, content.width)
        end
      end
    end

    struct Gauge
      getter ratio : Float64
      getter label : String?
      getter filled_style : Style
      getter unfilled_style : Style
      getter block : Block?

      def initialize(@ratio, @label = nil, @filled_style = Style.new, @unfilled_style = Style.new, @block = nil)
        @ratio = @ratio.clamp(0.0, 1.0)
      end

      def render(area : Rect, buffer : Buffer)
        content = area
        if block = @block
          block.render(area, buffer)
          content = block.inner(area)
        end
        return if content.empty?
        filled = (content.width * @ratio).round.to_i
        (0...content.width).each do |x|
          buffer.set_string(content.x + x, content.y, x < filled ? "█" : "░", x < filled ? @filled_style : @unfilled_style)
        end
        if label = @label
          start = content.x + ((content.width - label.size) // 2).clamp(0, Int32::MAX)
          buffer.set_string(start, content.y, label, Style.new, content.width)
        end
      end
    end

    struct Sparkline
      BARS = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']

      getter data : Array(Float64)
      getter style : Style

      def initialize(values : Enumerable(Number), @style = Style.new)
        @data = values.map(&.to_f64).to_a
      end

      def render(area : Rect, buffer : Buffer)
        return if area.empty? || @data.empty?
        values = @data.last(area.width)
        maximum = values.max
        values.each_with_index do |value, index|
          level = maximum > 0 ? (value / maximum * (BARS.size - 1)).round.to_i : 0
          buffer.set_string(area.x + index, area.y, BARS[level.clamp(0, BARS.size - 1)].to_s, @style)
        end
      end
    end
  end
end
