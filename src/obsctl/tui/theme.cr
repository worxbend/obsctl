require "../../crytui"

module Obsctl
  module TUI
    record Theme,
      id : String,
      label : String,
      background : CryTUI::Color,
      accent : CryTUI::Color,
      accent_alt : CryTUI::Color,
      foreground : CryTUI::Color,
      muted : CryTUI::Color,
      border : CryTUI::Color,
      border_focus : CryTUI::Color,
      success : CryTUI::Color,
      warning : CryTUI::Color,
      danger : CryTUI::Color,
      info : CryTUI::Color,
      highlight_background : CryTUI::Color,
      highlight_foreground : CryTUI::Color do
      CLAUDE = new(
        "claude", "Claude",
        rgb(0x1B, 0x19, 0x16), rgb(0xD9, 0x77, 0x57), rgb(0xE8, 0xC5, 0x9E),
        rgb(0xEC, 0xE8, 0xE1), rgb(0x8A, 0x86, 0x7D), rgb(0x4A, 0x46, 0x40),
        rgb(0xD9, 0x77, 0x57), rgb(0x87, 0xB3, 0x7B), rgb(0xE0, 0xB4, 0x4C),
        rgb(0xE0, 0x6C, 0x5F), rgb(0x7B, 0xA9, 0xC7), rgb(0xD9, 0x77, 0x57),
        rgb(0x1B, 0x19, 0x16)
      )

      NORD = new(
        "nord", "Nord",
        rgb(0x2E, 0x34, 0x40), rgb(0x88, 0xC0, 0xD0), rgb(0x81, 0xA1, 0xC1),
        rgb(0xE5, 0xE9, 0xF0), rgb(0x61, 0x6E, 0x88), rgb(0x3B, 0x42, 0x52),
        rgb(0x88, 0xC0, 0xD0), rgb(0xA3, 0xBE, 0x8C), rgb(0xEB, 0xCB, 0x8B),
        rgb(0xBF, 0x61, 0x6A), rgb(0x81, 0xA1, 0xC1), rgb(0x88, 0xC0, 0xD0),
        rgb(0x2E, 0x34, 0x40)
      )

      MONO = new(
        "mono", "Mono (TTY-safe)", CryTUI::Color::RESET, CryTUI::Color::WHITE,
        CryTUI::Color.indexed(8), CryTUI::Color::WHITE, CryTUI::Color.indexed(8),
        CryTUI::Color.indexed(8), CryTUI::Color::WHITE, CryTUI::Color::GREEN,
        CryTUI::Color::YELLOW, CryTUI::Color::RED, CryTUI::Color::CYAN,
        CryTUI::Color::WHITE, CryTUI::Color::BLACK
      )

      ALL = [CLAUDE, NORD, MONO]

      def self.default : Theme
        CLAUDE
      end

      def self.by_id(id : String) : Theme
        return default if id.downcase == "default"
        ALL.find { |theme| theme.id.downcase == id.downcase } || default
      end

      def self.parse_hex(value : String) : CryTUI::Color?
        hex = value.lstrip('#')
        return nil unless hex.matches?(/\A[0-9a-fA-F]{6}\z/)
        CryTUI::Color.rgb(hex[0, 2].to_i(16), hex[2, 2].to_i(16), hex[4, 2].to_i(16))
      end

      private def self.rgb(red, green, blue)
        CryTUI::Color.rgb(red, green, blue)
      end
    end
  end
end
