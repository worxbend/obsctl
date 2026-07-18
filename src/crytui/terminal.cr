module CryTUI
  abstract class Backend
    abstract def size : Rect
    abstract def draw(changes : Array(Tuple(Int32, Int32, Cell))) : Nil

    def enter : Nil
    end

    def leave : Nil
    end
  end

  class TestBackend < Backend
    getter buffer : Buffer

    def initialize(width : Int, height : Int)
      @buffer = Buffer.new(Rect.new(0, 0, width.to_i, height.to_i))
    end

    def size : Rect
      @buffer.area
    end

    def draw(changes : Array(Tuple(Int32, Int32, Cell))) : Nil
      changes.each do |x, y, cell|
        @buffer[x, y].symbol = cell.symbol
        @buffer[x, y].style = cell.style
      end
    end

    def resize(width : Int, height : Int)
      @buffer = Buffer.new(Rect.new(0, 0, width.to_i, height.to_i))
    end
  end

  class Frame
    getter area : Rect
    getter buffer : Buffer

    def initialize(@area, @buffer)
    end
  end

  class Terminal
    getter backend : Backend

    def initialize(@backend : Backend)
      @previous = Buffer.new(@backend.size)
      @active = false
    end

    def start : Nil
      return if @active
      @backend.enter
      @active = true
    end

    def stop : Nil
      return unless @active
      @backend.leave
      @active = false
    end

    def run(& : Terminal ->) : Nil
      start
      yield self
    ensure
      stop
    end

    def draw(& : Frame ->) : Nil
      area = @backend.size
      @previous = Buffer.new(area) unless @previous.area == area
      current = Buffer.new(area)
      yield Frame.new(area, current)
      @backend.draw(@previous.diff(current))
      @previous = current
    end
  end
end
