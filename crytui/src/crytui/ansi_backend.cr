module CryTUI
  # ANSI/VT backend for modern terminals. Capability negotiation and raw input
  # are separate concerns; this class owns output state and restoration only.
  class AnsiBackend < Backend
    getter io : IO

    # Button-event tracking reports presses, releases, and motion while a
    # button is held, which is what a drag needs; 1006 asks for SGR-encoded
    # coordinates so columns past 223 still report correctly.
    MOUSE_ON  = "\e[?1000h\e[?1002h\e[?1006h"
    MOUSE_OFF = "\e[?1006l\e[?1002l\e[?1000l"

    def initialize(@io : IO, width : Int, height : Int, @alternate_screen = true, @size_source : IO::FileDescriptor? = nil, @mouse = true)
      @area = Rect.new(0, 0, width.to_i, height.to_i)
      @last_style = Style.new
    end

    def self.for_terminal(io : IO, size_source : IO::FileDescriptor, alternate_screen = true, mouse = true) : self
      area = TerminalSize.from(size_source) || TerminalSize.from_environment || Rect.new(0, 0, 80, 24)
      new(io, area.width, area.height, alternate_screen, size_source, mouse)
    end

    def size : Rect
      @area
    end

    def resize(width : Int, height : Int)
      @area = Rect.new(0, 0, width.to_i, height.to_i)
    end

    def refresh_size : Bool
      source = @size_source
      return false unless source
      discovered = TerminalSize.from(source)
      return false unless discovered && discovered != @area
      @area = discovered
      true
    end

    def enter : Nil
      @io << "\e[?1049h" if @alternate_screen
      @io << MOUSE_ON if @mouse
      @io << "\e[?25l\e[?7l\e[2J\e[H"
      @io.flush
    end

    # Mouse tracking is released before the alternate screen, so a terminal that
    # survives the process still stops reporting. Leaving it on would spray
    # escape sequences into whatever shell prompt comes back.
    def leave : Nil
      @io << "\e[0m\e[?7h\e[?25h"
      @io << MOUSE_OFF if @mouse
      @io << "\e[?1049l" if @alternate_screen
      @io.flush
      @last_style = Style.new
    end

    def clear : Nil
      @io << "\e[0m\e[2J\e[H"
      @io.flush
      @last_style = Style.new
    end

    def draw(changes : Array(Tuple(Int32, Int32, Cell))) : Nil
      changes.each do |x, y, cell|
        next if cell.continuation?
        @io << "\e[#{y + 1};#{x + 1}H"
        write_style(cell.style) unless cell.style == @last_style
        @io << cell.symbol
      end
      @io.flush
    end

    private def write_style(style : Style)
      @io << "\e[0m"
      codes = [] of String
      modifiers = style.modifiers
      codes << "1" if modifiers.bold?
      codes << "2" if modifiers.dim?
      codes << "3" if modifiers.italic?
      codes << "4" if modifiers.underlined?
      codes << "7" if modifiers.reversed?
      codes << "8" if modifiers.hidden?
      codes << "9" if modifiers.crossed_out?
      append_color(codes, style.foreground, true)
      append_color(codes, style.background, false)
      @io << "\e[#{codes.join(';')}m" unless codes.empty?
      @last_style = style
    end

    private def append_color(codes : Array(String), color : Color?, foreground : Bool)
      return unless color
      prefix = foreground ? 38 : 48
      case color.kind
      when .reset?
        codes << (foreground ? "39" : "49")
      when .indexed?
        index = color.index
        if index < 8
          codes << ((foreground ? 30 : 40) + index).to_s
        elsif index < 16
          codes << ((foreground ? 90 : 100) + index - 8).to_s
        else
          codes << "#{prefix};5;#{index}"
        end
      when .rgb?
        codes << "#{prefix};2;#{color.red};#{color.green};#{color.blue}"
      end
    end
  end
end
