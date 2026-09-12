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
      return if changes.empty?

      rendered = String.build do |output|
        changes.each do |x, y, cell|
          next if cell.continuation?
          output << "\e[" << y + 1 << ';' << x + 1 << 'H'
          write_style(output, cell.style) unless cell.style == @last_style
          output << cell.symbol
        end
      end
      @io << rendered
      @io.flush
    end

    # One buffered escape stream avoids per-cell writes to the terminal, which
    # otherwise turn a large frame diff into hundreds of syscalls.
    private def write_style(output : IO, style : Style)
      output << "\e[0m"
      wrote_code = false
      modifiers = style.modifiers
      wrote_code = write_code(output, wrote_code, 1) if modifiers.bold?
      wrote_code = write_code(output, wrote_code, 2) if modifiers.dim?
      wrote_code = write_code(output, wrote_code, 3) if modifiers.italic?
      wrote_code = write_code(output, wrote_code, 4) if modifiers.underlined?
      wrote_code = write_code(output, wrote_code, 7) if modifiers.reversed?
      wrote_code = write_code(output, wrote_code, 8) if modifiers.hidden?
      wrote_code = write_code(output, wrote_code, 9) if modifiers.crossed_out?
      wrote_code = append_color(output, wrote_code, style.foreground, true)
      wrote_code = append_color(output, wrote_code, style.background, false)
      output << 'm' if wrote_code
      @last_style = style
    end

    private def append_color(output : IO, wrote_code : Bool, color : Color?, foreground : Bool) : Bool
      return wrote_code unless color

      prefix = foreground ? 38 : 48
      result = case color.kind
               when .reset?
                 write_code(output, wrote_code, foreground ? 39 : 49)
               when .indexed?
                 index = color.index
                 if index < 8
                   write_code(output, wrote_code, (foreground ? 30 : 40) + index)
                 elsif index < 16
                   write_code(output, wrote_code, (foreground ? 90 : 100) + index - 8)
                 else
                   write_color_triplet(output, wrote_code, prefix, 5, index)
                 end
               when .rgb?
                 write_rgb(output, wrote_code, prefix, color)
               else
                 wrote_code
               end
      result
    end

    private def write_code(output : IO, wrote_code : Bool, code : Int) : Bool
      output << "\e[" unless wrote_code
      output << ';' if wrote_code
      output << code
      true
    end

    private def write_color_triplet(output : IO, wrote_code : Bool, prefix : Int32, mode : Int32, value : UInt8) : Bool
      output << "\e[" unless wrote_code
      output << ';' if wrote_code
      output << prefix << ';' << mode << ';' << value
      true
    end

    private def write_rgb(output : IO, wrote_code : Bool, prefix : Int32, color : Color) : Bool
      output << "\e[" unless wrote_code
      output << ';' if wrote_code
      output << prefix << ";2;" << color.red << ';' << color.green << ';' << color.blue
      true
    end
  end
end
