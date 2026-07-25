module CryTUI
  class Cell
    property symbol : String
    property style : Style
    property? continuation : Bool

    def initialize(@symbol = " ", @style = Style.new, @continuation = false)
    end

    def reset
      @symbol = " "
      @style = Style.new
      @continuation = false
      self
    end

    def copy : Cell
      Cell.new(@symbol, @style, @continuation)
    end
  end

  class Buffer
    getter area : Rect
    getter cells : Array(Cell)

    def initialize(@area : Rect, fill = Cell.new)
      @cells = Array(Cell).new(@area.width * @area.height) { fill.copy }
    end

    def [](x : Int, y : Int) : Cell
      @cells[index(x, y)]
    end

    def []?(x : Int, y : Int) : Cell?
      return unless x >= @area.left && x < @area.right && y >= @area.top && y < @area.bottom
      @cells[index(x, y)]
    end

    def set_string(x : Int, y : Int, text : String, style = Style.new, max_width : Int? = nil) : Int32
      limit = {max_width || (@area.right - x), @area.right - x}.min.clamp(0, Int32::MAX)
      written = 0_i32
      text.each_grapheme do |grapheme|
        symbol = grapheme.to_s
        width = TextWidth.grapheme_width(symbol)
        next if width == 0
        break if written + width > limit
        if self[x + written, y]?
          clear_wide_at(x + written, y)
          cell = self[x + written, y]
          cell.symbol = symbol
          cell.style = cell.style.patch(style)
          cell.continuation = false
          if width == 2
            continuation = self[x + written + 1, y]
            clear_content(continuation)
            continuation.style = continuation.style.patch(style)
            continuation.continuation = true
          end
          written += width
        end
      end
      written
    end

    def set_style(area : Rect, style : Style)
      clipped = @area.intersection(area)
      (clipped.top...clipped.bottom).each do |y|
        (clipped.left...clipped.right).each { |x| self[x, y].style = self[x, y].style.patch(style) }
      end
    end

    def reset
      @cells.each(&.reset)
    end

    def diff(other : Buffer) : Array(Tuple(Int32, Int32, Cell))
      raise ArgumentError.new("buffer areas differ") unless @area == other.area
      changes = [] of Tuple(Int32, Int32, Cell)
      @cells.each_with_index do |cell, index|
        unless cell.symbol == other.cells[index].symbol && cell.style == other.cells[index].style && cell.continuation? == other.cells[index].continuation?
          x = @area.x + index % @area.width
          y = @area.y + index // @area.width
          changes << {x, y, other.cells[index]}
        end
      end
      changes
    end

    def copy : Buffer
      duplicate = Buffer.new(@area)
      @cells.each_with_index { |cell, index| duplicate.cells[index] = cell.copy }
      duplicate
    end

    def lines : Array(String)
      (0...@area.height).map do |row|
        String.build do |io|
          (0...@area.width).each do |column|
            cell = self[@area.x + column, @area.y + row]
            io << (cell.continuation? ? "" : cell.symbol)
          end
        end
      end
    end

    private def clear_wide_at(x : Int, y : Int)
      cell = self[x, y]
      if cell.continuation? && x > @area.left
        clear_content(self[x - 1, y])
      elsif TextWidth.width(cell.symbol) == 2 && x + 1 < @area.right
        clear_content(self[x + 1, y])
      end
      clear_content(cell)
    end

    private def clear_content(cell : Cell)
      cell.symbol = " "
      cell.continuation = false
    end

    private def index(x : Int, y : Int) : Int32
      raise IndexError.new("cell (#{x}, #{y}) outside #{@area}") unless x >= @area.left && x < @area.right && y >= @area.top && y < @area.bottom
      (y - @area.y) * @area.width + x - @area.x
    end
  end
end
