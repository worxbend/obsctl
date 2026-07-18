module CryTUI
  class Cell
    property symbol : String
    property style : Style

    def initialize(@symbol = " ", @style = Style.new)
    end

    def reset
      @symbol = " "
      @style = Style.new
      self
    end

    def copy : Cell
      Cell.new(@symbol, @style)
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
      return nil unless x >= @area.left && x < @area.right && y >= @area.top && y < @area.bottom
      @cells[index(x, y)]
    end

    def set_string(x : Int, y : Int, text : String, style = Style.new, max_width : Int? = nil) : Int32
      limit = {max_width || (@area.right - x), @area.right - x}.min.clamp(0, Int32::MAX)
      written = 0
      text.each_char do |char|
        break if written >= limit
        if cell = self[x + written, y]?
          cell.symbol = char.to_s
          cell.style = style
          written += 1
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
        unless cell.symbol == other.cells[index].symbol && cell.style == other.cells[index].style
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
        String.build { |io| (0...@area.width).each { |column| io << self[@area.x + column, @area.y + row].symbol } }
      end
    end

    private def index(x : Int, y : Int) : Int32
      raise IndexError.new("cell (#{x}, #{y}) outside #{@area}") unless x >= @area.left && x < @area.right && y >= @area.top && y < @area.bottom
      (y - @area.y) * @area.width + x - @area.x
    end
  end
end
