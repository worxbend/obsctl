require "../../crytui"

module Obsctl
  module TUI
    record CustomThemeSpec,
      background : String? = nil,
      accent : String? = nil,
      accent_alt : String? = nil,
      foreground : String? = nil,
      muted : String? = nil,
      border : String? = nil,
      border_focus : String? = nil,
      success : String? = nil,
      warning : String? = nil,
      danger : String? = nil,
      info : String? = nil,
      highlight_background : String? = nil,
      highlight_foreground : String? = nil

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
      CLAUDE           = palette("claude", "Claude", %w(1B1916 D97757 E8C59E ECE8E1 8A867D 4A4640 D97757 87B37B E0B44C E06C5F 7BA9C7 D97757 1B1916))
      CODEX            = palette("codex", "Codex", %w(0A1412 37E0B0 8AB4FF E3E8E6 6B7674 2A3331 37E0B0 37E0B0 F2C94C F25F5F 8AB4FF 37E0B0 0A1412))
      BTOP             = palette("btop", "Btop", %w(0A140A 6AE05A F0E050 D4E6D4 5A6A5A 304030 6AE05A 6AE05A F0E050 E05050 50C0E0 6AE05A 0A140A))
      NORD             = palette("nord", "Nord", %w(2E3440 88C0D0 81A1C1 E5E9F0 616E88 3B4252 88C0D0 A3BE8C EBCB8B BF616A 81A1C1 88C0D0 2E3440))
      DRACULA          = palette("dracula", "Dracula", %w(282A36 BD93F9 FF79C6 F8F8F2 6272A4 3A3D52 BD93F9 50FA7B F1FA8C FF5555 8BE9FD BD93F9 1E1F29))
      GRUVBOX          = palette("gruvbox", "Gruvbox", %w(282828 FE8019 D3869B EBDBB2 928374 3C3836 FE8019 B8BB26 FABD2F FB4934 83A598 FE8019 282828))
      SOLARIZED_DARK   = palette("solarized-dark", "Solarized Dark", %w(002B36 268BD2 2AA198 93A1A1 586E75 073642 268BD2 859900 B58900 DC322F 2AA198 268BD2 002B36))
      MONOKAI          = palette("monokai", "Monokai", %w(272822 A6E22E AE81FF F8F8F2 75715E 3E3D32 A6E22E A6E22E E6DB74 F92672 66D9EF A6E22E 272822))
      ONE_DARK         = palette("one-dark", "One Dark", %w(282C34 61AFEF C678DD ABB2BF 5C6370 3E4451 61AFEF 98C379 E5C07B E06C75 56B6C2 61AFEF 282C34))
      TOKYO_NIGHT      = palette("tokyo-night", "Tokyo Night", %w(1A1B26 7AA2F7 BB9AF7 C0CAF5 565F89 24283B 7AA2F7 9ECE6A E0AF68 F7768E 7DCFFF 7AA2F7 1A1B26))
      CATPPUCCIN_MOCHA = palette("catppuccin-mocha", "Catppuccin Mocha", %w(1E1E2E CBA6F7 89B4FA CDD6F4 A6ADC8 313244 CBA6F7 A6E3A1 F9E2AF F38BA8 89DCEB CBA6F7 1E1E2E))
      ROSE_PINE        = palette("rose-pine", "Rose Pine", %w(191724 C4A7E7 EBBCBA E0DEF4 6E6A86 26233A C4A7E7 9CCFD8 F6C177 EB6F92 9CCFD8 C4A7E7 191724))
      KANAGAWA_WAVE    = palette("kanagawa-wave", "Kanagawa Wave", %w(1F1F28 7E9CD8 957FB8 DCD7BA 727169 2A2A37 7E9CD8 98BB6C E6C384 E82424 7FB4CA 7E9CD8 1F1F28))
      EVERFOREST_DARK  = palette("everforest-dark", "Everforest Dark", %w(2D353B A7C080 D699B6 D3C6AA 859289 475258 A7C080 A7C080 DBBC7F E67E80 7FBBB3 A7C080 2D353B))
      AYU_MIRAGE       = palette("ayu-mirage", "Ayu Mirage", %w(1F2430 FFB454 D2A6FF CBCCC6 707A8C 343D46 FFB454 BAE67E FFD580 F28779 5CCFE6 FFB454 1F2430))
      GITHUB_DARK      = palette("github-dark", "GitHub Dark", %w(0D1117 58A6FF BC8CFF C9D1D9 8B949E 30363D 58A6FF 3FB950 D29922 F85149 58A6FF 58A6FF 0D1117))
      SOLARIZED_LIGHT  = palette("solarized-light", "Solarized Light", %w(FDF6E3 268BD2 2AA198 657B83 93A1A1 EEE8D5 268BD2 859900 B58900 DC322F 2AA198 268BD2 FDF6E3))
      CATPPUCCIN_LATTE = palette("catppuccin-latte", "Catppuccin Latte", %w(EFF1F5 8839EF 1E66F5 4C4F69 9CA0B0 CCD0DA 8839EF 40A02B DF8E1D D20F39 04A5E5 8839EF EFF1F5))
      GITHUB_LIGHT     = palette("github-light", "GitHub Light", %w(FFFFFF 0969DA 8250DF 1F2328 656D76 D0D7DE 0969DA 1A7F37 9A6700 CF222E 0969DA 0969DA FFFFFF))
      ROSE_PINE_DAWN   = palette("rose-pine-dawn", "Rose Pine Dawn", %w(FAF4ED D7827E 907AA9 575279 9893A5 F2E9E1 D7827E 56949F EA9D34 B4637A 286983 D7827E FAF4ED))
      NIGHT_OWL        = palette("night-owl", "Night Owl", %w(011627 82AAFF C792EA D6DEEB 637777 1D3B53 82AAFF 22DA6E ECC48D EF5350 21C7A8 82AAFF 011627))
      MATERIAL_OCEAN   = palette("material-ocean", "Material Ocean", %w(0F111A 84FFFF C792EA 8F93A2 464B5D 1A1C25 84FFFF C3E88D FFCB6B F07178 89DDFF 84FFFF 0F111A))
      HORIZON          = palette("horizon", "Horizon", %w(1C1E26 E95678 B877DB D5D8DA 6C6F93 2E303E E95678 29D398 FAB795 EC6A88 26BBD9 E95678 1C1E26))
      ICEBERG          = palette("iceberg", "Iceberg", %w(161821 84A0C6 A093C7 C6C8D1 6B7089 2E313F 84A0C6 B4BE82 E2A478 E27878 89B8C2 84A0C6 161821))
      MOONFLY          = palette("moonfly", "Moonfly", %w(080808 80A0FF CF87E8 BDBDBD 808080 323437 80A0FF 8CC85F E3C78A FF5189 79DAC8 80A0FF 080808))
      SYNTHWAVE_84     = palette("synthwave-84", "Synthwave '84", %w(262335 FF7EDB 36F9F6 FFFFFF 848BBD 495495 FF7EDB 72F1B8 FEDE5D FE4450 03EDF9 FF7EDB 262335))
      MATRIX           = palette("matrix", "Matrix", %w(050B05 00FF41 00CC33 D8FFD8 397D39 0F3D0F 00FF41 00FF41 CFFF04 FF3B30 39FF14 00FF41 050B05))
      ZENBURN          = palette("zenburn", "Zenburn", %w(3F3F3F DCA3A3 8CD0D3 DCDCCC 7F9F7F 5F5F5F DCA3A3 7F9F7F F0DFAF CC9393 8CD0D3 DCA3A3 3F3F3F))
      MONO             = new("mono", "Mono (TTY-safe)", CryTUI::Color::RESET, CryTUI::Color::WHITE, CryTUI::Color::GRAY, CryTUI::Color::WHITE, CryTUI::Color::DARK_GRAY, CryTUI::Color::DARK_GRAY, CryTUI::Color::WHITE, CryTUI::Color::GREEN, CryTUI::Color::YELLOW, CryTUI::Color::RED, CryTUI::Color::CYAN, CryTUI::Color::WHITE, CryTUI::Color::BLACK)

      ALL = [CLAUDE, CODEX, BTOP, NORD, DRACULA, GRUVBOX, SOLARIZED_DARK, MONOKAI, ONE_DARK, TOKYO_NIGHT, CATPPUCCIN_MOCHA, ROSE_PINE, KANAGAWA_WAVE, EVERFOREST_DARK, AYU_MIRAGE, GITHUB_DARK, SOLARIZED_LIGHT, CATPPUCCIN_LATTE, GITHUB_LIGHT, ROSE_PINE_DAWN, NIGHT_OWL, MATERIAL_OCEAN, HORIZON, ICEBERG, MOONFLY, SYNTHWAVE_84, MATRIX, ZENBURN, MONO]

      def self.default : Theme
        CLAUDE
      end

      def self.by_id(id : String) : Theme
        return default if id.downcase == "default"
        ALL.find { |theme| theme.id.downcase == id.downcase } || default
      end

      def self.resolve(id : String, custom : CustomThemeSpec? = nil) : Theme
        id.downcase == "custom" ? from_custom(custom || CustomThemeSpec.new) : by_id(id)
      end

      def self.from_custom(spec : CustomThemeSpec) : Theme
        base = default
        new(
          "custom", "Custom",
          pick(spec.background, base.background), pick(spec.accent, base.accent),
          pick(spec.accent_alt, base.accent_alt), pick(spec.foreground, base.foreground),
          pick(spec.muted, base.muted), pick(spec.border, base.border),
          pick(spec.border_focus, base.border_focus), pick(spec.success, base.success),
          pick(spec.warning, base.warning), pick(spec.danger, base.danger),
          pick(spec.info, base.info), pick(spec.highlight_background, base.highlight_background),
          pick(spec.highlight_foreground, base.highlight_foreground)
        )
      end

      def self.parse_hex(value : String) : CryTUI::Color?
        hex = value.lstrip('#')
        return nil unless hex.matches?(/\A[0-9a-fA-F]{6}\z/)
        CryTUI::Color.rgb(hex[0, 2].to_i(16), hex[2, 2].to_i(16), hex[4, 2].to_i(16))
      end

      private def self.palette(id : String, label : String, colors : Array(String)) : Theme
        parsed = colors.map { |color| parse_hex(color) || raise "invalid built-in theme color: #{color}" }
        new(
          id, label,
          parsed[0], parsed[1], parsed[2], parsed[3], parsed[4], parsed[5], parsed[6],
          parsed[7], parsed[8], parsed[9], parsed[10], parsed[11], parsed[12]
        )
      end

      private def self.pick(value : String?, fallback : CryTUI::Color) : CryTUI::Color
        value.try { |color| parse_hex(color) } || fallback
      end
    end
  end
end
