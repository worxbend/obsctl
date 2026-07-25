module CryTUI
  enum KeyCode
    Character
    Enter
    Escape
    Backspace
    Tab
    BackTab
    Up
    Down
    Left
    Right
    Home
    End
    Delete
    PageUp
    PageDown
    Function
  end

  @[Flags]
  enum KeyModifiers
    Shift
    Alt
    Control
  end

  struct KeyEvent
    getter code : KeyCode
    getter character : Char?
    getter function : Int32?
    getter modifiers : KeyModifiers

    def initialize(@code, @character = nil, @function = nil, @modifiers = KeyModifiers::None)
    end

    def self.character(character : Char, modifiers = KeyModifiers::None)
      new(KeyCode::Character, character: character, modifiers: modifiers)
    end
  end

  struct PasteEvent
    getter text : String

    def initialize(@text)
    end
  end

  alias InputEvent = KeyEvent | PasteEvent

  # Incremental VT input parser for the keys used by obsctl. It accepts chunks
  # because escape sequences and UTF-8 input may straddle reads.
  class InputParser
    PASTE_START = "\e[200~"
    PASTE_END   = "\e[201~"

    def initialize
      @pending = ""
      @pasting = false
      @paste = ""
    end

    def feed(chunk : String) : Array(InputEvent)
      @pending += chunk
      events = [] of InputEvent
      loop do
        if @pasting
          if index = @pending.index(PASTE_END)
            @paste += @pending.byte_slice(0, index)
            events << PasteEvent.new(@paste)
            @paste = ""
            @pasting = false
            @pending = @pending.byte_slice(index + PASTE_END.bytesize)
            next
          end
          keep = {PASTE_END.bytesize - 1, @pending.bytesize}.min
          consumed = @pending.bytesize - keep
          @paste += @pending.byte_slice(0, consumed) if consumed > 0
          @pending = @pending.byte_slice(consumed)
          break
        end

        break if @pending.empty?
        if @pending.starts_with?(PASTE_START)
          @pending = @pending.byte_slice(PASTE_START.bytesize)
          @pasting = true
          next
        end
        if PASTE_START.starts_with?(@pending) && @pending.bytesize < PASTE_START.bytesize
          break
        end
        if @pending.starts_with?("\e")
          parsed = parse_escape
          break unless parsed
          event, consumed = parsed
          events << event
          @pending = @pending.byte_slice(consumed)
          next
        end
        char = @pending.each_char.first
        bytes = char.bytesize
        events << parse_character(char)
        @pending = @pending.byte_slice(bytes)
      end
      events
    end

    # Resolve a lone escape byte after the caller's escape-delay expires.
    def flush_escape : Array(InputEvent)
      return [] of InputEvent unless @pending == "\e"
      @pending = ""
      [KeyEvent.new(KeyCode::Escape)] of InputEvent
    end

    private def parse_character(char : Char) : KeyEvent
      case char.ord
      when 0x03       then KeyEvent.character('c', KeyModifiers::Control)
      when 0x08, 0x7F then KeyEvent.new(KeyCode::Backspace)
      when 0x09       then KeyEvent.new(KeyCode::Tab)
      when 0x0A, 0x0D then KeyEvent.new(KeyCode::Enter)
      when 0x01..0x1A
        KeyEvent.character((char.ord + 0x60).chr, KeyModifiers::Control)
      else
        KeyEvent.character(char)
      end
    end

    private def parse_escape : Tuple(KeyEvent, Int32)?
      return if @pending.bytesize == 1
      sequences = {
        "\e[A"    => KeyEvent.new(KeyCode::Up),
        "\e[B"    => KeyEvent.new(KeyCode::Down),
        "\e[C"    => KeyEvent.new(KeyCode::Right),
        "\e[D"    => KeyEvent.new(KeyCode::Left),
        "\e[1;5A" => KeyEvent.new(KeyCode::Up, modifiers: KeyModifiers::Control),
        "\e[1;5B" => KeyEvent.new(KeyCode::Down, modifiers: KeyModifiers::Control),
        "\e[1;5C" => KeyEvent.new(KeyCode::Right, modifiers: KeyModifiers::Control),
        "\e[1;5D" => KeyEvent.new(KeyCode::Left, modifiers: KeyModifiers::Control),
        "\e[Z"    => KeyEvent.new(KeyCode::BackTab, modifiers: KeyModifiers::Shift),
        "\e[H"    => KeyEvent.new(KeyCode::Home),
        "\e[F"    => KeyEvent.new(KeyCode::End),
        "\e[3~"   => KeyEvent.new(KeyCode::Delete),
        "\e[5~"   => KeyEvent.new(KeyCode::PageUp),
        "\e[6~"   => KeyEvent.new(KeyCode::PageDown),
        "\eOQ"    => KeyEvent.new(KeyCode::Function, function: 2),
        "\e[12~"  => KeyEvent.new(KeyCode::Function, function: 2),
      }
      if match = sequences.find { |sequence, _| @pending.starts_with?(sequence) }
        return {match[1], match[0].bytesize}
      end
      return if sequences.any? { |sequence, _| sequence.starts_with?(@pending) }

      # Unknown complete CSI/SS3 sequences are consumed as Escape so malformed
      # input cannot permanently stall the parser.
      if @pending.starts_with?("\e[") || @pending.starts_with?("\eO")
        if match = @pending.match(/\A\e(?:\[[0-9;?]*[ -\/]?[@-~]|O.)/)
          return {KeyEvent.new(KeyCode::Escape), match[0].bytesize}
        end
        return
      end

      # Alt-modified printable character.
      char = @pending.byte_slice(1).each_char.first
      {KeyEvent.character(char, KeyModifiers::Alt), 1 + char.bytesize}
    end
  end
end
