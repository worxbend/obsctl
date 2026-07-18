module CryTUI
  enum ColorKind
    Reset
    Indexed
    Rgb
  end

  struct Color
    getter kind : ColorKind
    getter red : UInt8
    getter green : UInt8
    getter blue : UInt8
    getter index : UInt8

    private def initialize(@kind, @red = 0_u8, @green = 0_u8, @blue = 0_u8, @index = 0_u8)
    end

    RESET     = new(ColorKind::Reset)
    BLACK     = indexed(0)
    RED       = indexed(1)
    GREEN     = indexed(2)
    YELLOW    = indexed(3)
    BLUE      = indexed(4)
    MAGENTA   = indexed(5)
    CYAN      = indexed(6)
    GRAY      = indexed(7)
    DARK_GRAY = indexed(8)
    WHITE     = indexed(15)

    def self.indexed(index : Int) : Color
      new(ColorKind::Indexed, index: index.clamp(0, 255).to_u8)
    end

    def self.rgb(red : Int, green : Int, blue : Int) : Color
      new(ColorKind::Rgb, red.clamp(0, 255).to_u8, green.clamp(0, 255).to_u8, blue.clamp(0, 255).to_u8)
    end
  end

  @[Flags]
  enum Modifier
    Bold
    Dim
    Italic
    Underlined
    Reversed
    Hidden
    CrossedOut
  end

  struct Style
    property foreground : Color?
    property background : Color?
    property modifiers : Modifier

    def initialize(@foreground = nil, @background = nil, @modifiers = Modifier::None)
    end

    def patch(other : Style) : Style
      Style.new(other.foreground || @foreground, other.background || @background, @modifiers | other.modifiers)
    end
  end
end
