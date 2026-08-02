module CryTUI
  module Widgets
    @[Flags]
    enum Borders
      Top
      Right
      Bottom
      Left
    end

    struct BorderSet
      getter top_left : String
      getter top_right : String
      getter bottom_left : String
      getter bottom_right : String
      getter horizontal : String
      getter vertical : String

      def initialize(@top_left, @top_right, @bottom_left, @bottom_right, @horizontal, @vertical)
      end

      ASCII   = new("+", "+", "+", "+", "-", "|")
      PLAIN   = new("┌", "┐", "└", "┘", "─", "│")
      ROUNDED = new("╭", "╮", "╰", "╯", "─", "│")
      THICK   = new("┏", "┓", "┗", "┛", "━", "┃")
      DOUBLE  = new("╔", "╗", "╚", "╝", "═", "║")
    end

    struct Block
      getter title : String | Line?
      getter borders : Borders
      getter style : Style
      getter border_style : Style
      getter border_set : BorderSet

      def initialize(@title : String | Line? = nil, @borders = Borders::All, @style = Style.new, @border_style = Style.new, @border_set = BorderSet::PLAIN)
      end

      def inner(area : Rect) : Rect
        left = @borders.left? ? 1 : 0
        top = @borders.top? ? 1 : 0
        right = @borders.right? ? 1 : 0
        bottom = @borders.bottom? ? 1 : 0
        Rect.new(
          area.x + left,
          area.y + top,
          {area.width - left - right, 0}.max,
          {area.height - top - bottom, 0}.max
        )
      end

      def render(area : Rect, buffer : Buffer)
        return if area.empty?
        buffer.set_style(area, @style)
        left, right, top, bottom = area.left, area.right - 1, area.top, area.bottom - 1
        if @borders.top?
          (left..right).each do |x|
            symbol = if x == left && @borders.left?
                       @border_set.top_left
                     elsif x == right && @borders.right?
                       @border_set.top_right
                     else
                       @border_set.horizontal
                     end
            set_border(buffer, x, top, symbol)
          end
        end
        if @borders.bottom? && bottom != top
          (left..right).each do |x|
            symbol = if x == left && @borders.left?
                       @border_set.bottom_left
                     elsif x == right && @borders.right?
                       @border_set.bottom_right
                     else
                       @border_set.horizontal
                     end
            set_border(buffer, x, bottom, symbol)
          end
        end
        vertical_top = top + (@borders.top? ? 1 : 0)
        vertical_bottom = bottom - (@borders.bottom? ? 1 : 0)
        if vertical_top <= vertical_bottom
          (vertical_top..vertical_bottom).each do |y|
            set_border(buffer, left, y, @border_set.vertical) if @borders.left?
            set_border(buffer, right, y, @border_set.vertical) if @borders.right? && right != left
          end
        end
        if (title = @title) && area.width >= 4
          # Ratatui writes titles directly after the left border and does not
          # synthesize padding. Callers include any desired surrounding spaces
          # in the title itself.
          title_x = left + (@borders.left? ? 1 : 0)
          title_line = case title
                       when Line
                         title
                       else
                         Line.from(title, @border_style)
                       end
          title_right = area.right - (@borders.right? ? 1 : 0)
          title_line.render(buffer, Rect.new(title_x, top, {title_right - title_x, 0}.max, 1), @border_style)
        end
      end

      # Adjacent blocks may deliberately overlap by one row or column. Merge
      # their directional strokes into a real box-drawing junction instead of
      # letting the later block replace the earlier corner.
      private def set_border(buffer : Buffer, x : Int, y : Int, symbol : String)
        incoming = border_connections(symbol)
        existing = buffer[x, y]?.try { |cell| border_connections(cell.symbol) }
        rendered = if incoming && existing
                     border_symbol(incoming | existing)
                   else
                     symbol
                   end
        buffer.set_string(x, y, rendered, @border_style)
      end

      private def border_connections(symbol : String) : Int32?
        case symbol
        when "─", "━", "═"      then 0b0011 # left | right
        when "│", "┃", "║"      then 0b1100 # up | down
        when "┌", "╭", "┏", "╔" then 0b1010 # right | down
        when "┐", "╮", "┓", "╗" then 0b1001 # left | down
        when "└", "╰", "┗", "╚" then 0b0110 # right | up
        when "┘", "╯", "┛", "╝" then 0b0101 # left | up
        when "├"                then 0b1110
        when "┤"                then 0b1101
        when "┬"                then 0b1011
        when "┴"                then 0b0111
        when "┼"                then 0b1111
        end
      end

      private def border_symbol(connections : Int32) : String
        case connections
        when 0b0011 then @border_set.horizontal
        when 0b1100 then @border_set.vertical
        when 0b1010 then @border_set.top_left
        when 0b1001 then @border_set.top_right
        when 0b0110 then @border_set.bottom_left
        when 0b0101 then @border_set.bottom_right
        when 0b1110 then "├"
        when 0b1101 then "┤"
        when 0b1011 then "┬"
        when 0b0111 then "┴"
        when 0b1111 then "┼"
        else             @border_set.horizontal
        end
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

    struct StyledText
      getter lines : Array(Line)
      getter style : Style
      getter block : Block?
      getter scroll : Int32

      def initialize(@lines, @style = Style.new, @block = nil, @scroll = 0)
      end

      def render(area : Rect, buffer : Buffer)
        content = area
        if block = @block
          block.render(area, buffer)
          content = block.inner(area)
        end
        return if content.empty?
        @lines.skip(@scroll.clamp(0, Int32::MAX)).first(content.height).each_with_index do |line, index|
          line.render(buffer, Rect.new(content.x, content.y + index, content.width, 1), @style)
        end
      end
    end

    struct ListItem
      getter lines : Array(Line)
      getter style : Style

      def initialize(@lines, @style = Style.new)
      end

      def self.from(text : String, style = Style.new)
        new([Line.from(text)], style)
      end

      def height : Int32
        @lines.size
      end
    end

    class ListState
      property selected : Int32?
      property offset : Int32

      def initialize(@selected = nil, @offset = 0)
      end
    end

    struct List
      getter items : Array(ListItem)
      getter style : Style
      getter highlight_style : Style
      getter block : Block?

      def initialize(@items, @style = Style.new, @highlight_style = Style.new, @block = nil)
      end

      def render(area : Rect, buffer : Buffer, state : ListState)
        content = area
        if block = @block
          block.render(area, buffer)
          content = block.inner(area)
        end
        return if content.empty? || @items.empty?
        clamp_state(state, content.height)
        y = content.y
        @items.each_with_index.skip(state.offset).each do |item, index|
          break if y >= content.bottom
          selected = state.selected == index
          visible_height = {item.height, content.bottom - y}.min
          inherited = @style.patch(item.style)
          inherited = inherited.patch(@highlight_style) if selected
          if selected
            buffer.set_style(Rect.new(content.x, y, content.width, visible_height), inherited)
          end
          item.lines.first(visible_height).each do |line|
            line.render(buffer, Rect.new(content.x, y, content.width, 1), inherited)
            y += 1
          end
        end
      end

      # The index of the first item the list will draw, from the item heights,
      # the selection, and the rows available. Anything that needs to know where
      # an item ended up on screen -- hit testing, most obviously -- has to
      # reach the same answer the renderer did, so both come through here.
      def self.visible_offset(heights : Array(Int32), selected : Int32?, height : Int32, offset : Int32 = 0) : Int32
        return offset.clamp(0, {heights.size - 1, 0}.max) unless selected
        selected = selected.clamp(0, heights.size - 1)
        offset = {offset, selected}.min.clamp(0, Int32::MAX)
        while rows(heights, offset, selected) > height
          offset += 1
        end
        offset
      end

      private def self.rows(heights : Array(Int32), from : Int32, through : Int32) : Int32
        return 0 if from > through
        heights[from..through].sum
      end

      private def clamp_state(state : ListState, height : Int32)
        selected = state.selected
        return state.offset = state.offset.clamp(0, {@items.size - 1, 0}.max) unless selected
        state.selected = selected.clamp(0, @items.size - 1)
        state.offset = List.visible_offset(@items.map(&.height), state.selected, height, state.offset)
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
