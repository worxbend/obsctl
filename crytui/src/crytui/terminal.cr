module CryTUI
  abstract class Backend
    abstract def size : Rect
    abstract def draw(changes : Array(Tuple(Int32, Int32, Cell))) : Nil

    def enter : Nil
    end

    def leave : Nil
    end

    def refresh_size : Bool
      false
    end

    def clear : Nil
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
        target = @buffer[x, y]
        target.symbol = cell.symbol
        target.style = cell.style
        target.continuation = cell.continuation?
      end
    end

    def clear : Nil
      @buffer.reset
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

    def area : Rect
      @backend.size
    end

    def initialize(@backend : Backend)
      @previous = Buffer.new(@backend.size)
      @current = Buffer.new(@backend.size)
      @active = false
      @force_full_redraw = false
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

    # Runs with the input descriptor in raw mode and restores its exact prior
    # termios state after normal return or an exception.
    def run(input : IO::FileDescriptor, & : Terminal ->) : Nil
      input.raw do
        run { |terminal| yield terminal }
      end
    end

    def refresh_size : Bool
      changed = @backend.refresh_size
      synchronize_area
      changed
    end

    def draw(& : Frame ->) : Nil
      refresh_size
      area = @current.area
      current = @current
      current.reset
      yield Frame.new(area, current)
      changes = @force_full_redraw ? current.all_cells : @previous.diff(current)
      @backend.draw(changes)
      @previous, @current = current, @previous
      @force_full_redraw = false
    end

    private def synchronize_area : Nil
      area = @backend.size
      return if @previous.area == area

      @backend.clear
      @previous = Buffer.new(area)
      @current = Buffer.new(area)
      @force_full_redraw = true
    end
  end
end
