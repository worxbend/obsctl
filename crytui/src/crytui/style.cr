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

    # WCAG relative luminance: how bright this colour reads to the eye, 0 to 1.
    #
    # The per-channel curve undoes the sRGB gamma encoding, and the weights are
    # the eye's differing sensitivity to red, green and blue — which is why a
    # saturated blue reads far darker than a green of the same numeric value.
    #
    # Only meaningful for RGB colours; an indexed or reset colour is whatever
    # the terminal's palette says it is, which this code cannot know.
    def relative_luminance : Float64?
      return unless kind.rgb?

      0.2126 * channel_luminance(@red) + 0.7152 * channel_luminance(@green) + 0.0722 * channel_luminance(@blue)
    end

    private def channel_luminance(value : UInt8) : Float64
      scaled = value.to_f64 / 255.0
      scaled <= 0.03928 ? scaled / 12.92 : ((scaled + 0.055) / 1.055) ** 2.4
    end

    # WCAG contrast ratio between two colours, from 1.0 (identical) to 21.0
    # (black on white). Nil when either colour is not RGB.
    def self.contrast_ratio(first : Color, second : Color) : Float64?
      first_luminance = first.relative_luminance
      second_luminance = second.relative_luminance
      return unless first_luminance && second_luminance

      lighter = {first_luminance, second_luminance}.max
      darker = {first_luminance, second_luminance}.min
      (lighter + 0.05) / (darker + 0.05)
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

  # Rescues text that would be unreadable on the background it lands on.
  #
  # A widget picks each span's colour for the ordinary background — an index in
  # a muted grey, a shortcut in amber. When a row is repainted in different
  # colours, some of those choices stop working: on a dim selection bar a muted
  # grey can come within 1.05:1 of the bar itself, which is invisible. Rather
  # than flatten every span to one colour, which would also erase the ones that
  # are perfectly readable and carrying meaning, this replaces only the ones
  # that fail.
  record ForegroundGuard,
    replacement : Color,
    background : Color,
    minimum_contrast : Float64 do
    # Returns true when `foreground` is too close to `background` to read.
    #
    # A nil foreground already inherits the row's own colour, and a non-RGB
    # colour has no measurable luminance, so neither is second-guessed.
    def insufficient?(foreground : Color?) : Bool
      return false unless foreground

      ratio = Color.contrast_ratio(foreground, @background)
      return false unless ratio

      ratio < @minimum_contrast
    end
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

    # Returns this style with `foreground` replaced, ignoring what it was.
    #
    # `patch` deliberately lets the more specific style win, which is right
    # almost everywhere. Where it is not — a selection bar whose own colour
    # has to beat the per-span colours chosen for the ordinary background —
    # this overrides in the other direction.
    def with_foreground(color : Color?) : Style
      return self unless color

      Style.new(color, @background, @modifiers)
    end
  end
end
