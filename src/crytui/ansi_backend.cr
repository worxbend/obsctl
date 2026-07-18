module CryTUI
  # ANSI/VT backend for modern terminals. Capability negotiation and raw input
  # are separate concerns; this class owns output state and restoration only.
  class AnsiBackend < Backend
    getter io : IO

    def initialize(@io : IO, width : Int, height : Int, @alternate_screen = true)
      @area = Rect.new(0, 0, width.to_i, height.to_i)
      @last_style = Style.new
    end

    def size : Rect
      @area
    end

    def resize(width : Int, height : Int)
      @area = Rect.new(0, 0, width.to_i, height.to_i)
    end

    def enter : Nil
      @io << "\e[?1049h" if @alternate_screen
      @io << "\e[?25l\e[2J\e[H"
      @io.flush
    end

    def leave : Nil
      @io << "\e[0m\e[?25h"
      @io << "\e[?1049l" if @alternate_screen
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
