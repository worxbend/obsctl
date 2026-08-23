module CryTUI
  enum Alignment
    Left
    Center
    Right
  end

  struct Span
    getter content : String
    getter style : Style

    def initialize(@content, @style = Style.new)
    end

    def width : Int32
      TextWidth.width(@content)
    end
  end

  struct Line
    getter spans : Array(Span)
    getter alignment : Alignment
    getter style : Style

    def initialize(@spans = [] of Span, @alignment = Alignment::Left, @style = Style.new)
    end

    def self.from(text : String, style = Style.new, alignment = Alignment::Left)
      new([Span.new(text, style)], alignment)
    end

    def width : Int32
      @spans.sum(&.width)
    end

    # Draws the line's spans across `area`.
    #
    # `guard` rescues spans whose own colour is unreadable on the background
    # they end up on. It exists for the selected row of a list: each span picks
    # a colour for the ordinary background — an index in `muted`, a shortcut in
    # `warning` — and some of those choices stop working once the row is
    # repainted in the highlight colours.
    def render(buffer : Buffer, area : Rect, inherited_style = Style.new, guard : ForegroundGuard? = nil)
      return if area.empty?
      start = case @alignment
              when .center? then area.x + ((area.width - width) // 2).clamp(0, Int32::MAX)
              when .right?  then area.x + (area.width - width).clamp(0, Int32::MAX)
              else               area.x
              end
      remaining = area.right - start
      cursor = start
      base = inherited_style.patch(@style)
      @spans.each do |span|
        break if remaining <= 0
        style = base.patch(span.style)
        style = style.with_foreground(guard.replacement) if guard && guard.insufficient?(style.foreground)
        written = buffer.set_string(cursor, area.y, span.content, style, remaining)
        cursor += written
        remaining -= written
      end
    end
  end
end
