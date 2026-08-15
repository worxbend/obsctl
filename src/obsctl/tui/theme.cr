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
      # Colours for a count badge: the small inverse chip in a panel title,
      # like the " 03 " next to "Scenes".
      #
      # Deliberately not the highlight pair. The two look superficially alike —
      # both are "text on a coloured block" — but they want opposite things. A
      # selection bar is a dim wash that has to sit behind a whole row of text
      # without drowning it; a badge is a small bright chip that has to stand
      # out from the panel title beside it. Sharing one pair meant that dimming
      # the selection bar also flattened every badge into the background.
      def badge_background : CryTUI::Color
        accent
      end

      # :ditto:
      def badge_foreground : CryTUI::Color
        background
      end

      # How much of the accent survives in a selection bar, from 0 (invisible)
      # to 1 (a solid slab of accent). A terminal cell has no alpha channel --
      # there is no way to ask it for "30% opaque" -- so the see-through look
      # is baked into the colour instead: `tint` mixes the accent into the
      # theme background at this ratio and stores the result, which is exactly
      # what the terminal would have shown had it been able to composite the
      # two itself. 0.28 was picked because it is enough for the selected row
      # to read as selected at a glance, and little enough that the row's own
      # text -- which keeps the colours it was given for the plain background,
      # see below -- stays as legible as every other row.
      HIGHLIGHT_TINT = 0.28

      EMBER            = palette("ember", "Ember", %w[1B1916 D97757 E8C59E ECE8E1 8A867D 4A4640 D97757 87B37B E0B44C E06C5F 7BA9C7])
      SLATE            = palette("slate", "Slate", %w[0A1412 37E0B0 8AB4FF E3E8E6 6B7674 2A3331 37E0B0 37E0B0 F2C94C F25F5F 8AB4FF])
      BTOP             = palette("btop", "Btop", %w[0A140A 6AE05A F0E050 D4E6D4 5A6A5A 304030 6AE05A 6AE05A F0E050 E05050 50C0E0])
      NORD             = palette("nord", "Nord", %w[2E3440 88C0D0 81A1C1 E5E9F0 616E88 3B4252 88C0D0 A3BE8C EBCB8B BF616A 81A1C1])
      DRACULA          = palette("dracula", "Dracula", %w[282A36 BD93F9 FF79C6 F8F8F2 6272A4 3A3D52 BD93F9 50FA7B F1FA8C FF5555 8BE9FD])
      GRUVBOX          = palette("gruvbox", "Gruvbox", %w[282828 FE8019 D3869B EBDBB2 928374 3C3836 FE8019 B8BB26 FABD2F FB4934 83A598])
      SOLARIZED_DARK   = palette("solarized-dark", "Solarized Dark", %w[002B36 268BD2 2AA198 93A1A1 586E75 073642 268BD2 859900 B58900 DC322F 2AA198])
      MONOKAI          = palette("monokai", "Monokai", %w[272822 A6E22E AE81FF F8F8F2 75715E 3E3D32 A6E22E A6E22E E6DB74 F92672 66D9EF])
      ONE_DARK         = palette("one-dark", "One Dark", %w[282C34 61AFEF C678DD ABB2BF 5C6370 3E4451 61AFEF 98C379 E5C07B E06C75 56B6C2])
      TOKYO_NIGHT      = palette("tokyo-night", "Tokyo Night", %w[1A1B26 7AA2F7 BB9AF7 C0CAF5 565F89 24283B 7AA2F7 9ECE6A E0AF68 F7768E 7DCFFF])
      CATPPUCCIN_MOCHA = palette("catppuccin-mocha", "Catppuccin Mocha", %w[1E1E2E CBA6F7 89B4FA CDD6F4 A6ADC8 313244 CBA6F7 A6E3A1 F9E2AF F38BA8 89DCEB])
      ROSE_PINE        = palette("rose-pine", "Rose Pine", %w[191724 C4A7E7 EBBCBA E0DEF4 6E6A86 26233A C4A7E7 9CCFD8 F6C177 EB6F92 9CCFD8])
      KANAGAWA_WAVE    = palette("kanagawa-wave", "Kanagawa Wave", %w[1F1F28 7E9CD8 957FB8 DCD7BA 727169 2A2A37 7E9CD8 98BB6C E6C384 E82424 7FB4CA])
      EVERFOREST_DARK  = palette("everforest-dark", "Everforest Dark", %w[2D353B A7C080 D699B6 D3C6AA 859289 475258 A7C080 A7C080 DBBC7F E67E80 7FBBB3])
      AYU_MIRAGE       = palette("ayu-mirage", "Ayu Mirage", %w[1F2430 FFB454 D2A6FF CBCCC6 707A8C 343D46 FFB454 BAE67E FFD580 F28779 5CCFE6])
      GITHUB_DARK      = palette("github-dark", "GitHub Dark", %w[0D1117 58A6FF BC8CFF C9D1D9 8B949E 30363D 58A6FF 3FB950 D29922 F85149 58A6FF])
      SOLARIZED_LIGHT  = palette("solarized-light", "Solarized Light", %w[FDF6E3 268BD2 2AA198 657B83 93A1A1 EEE8D5 268BD2 859900 B58900 DC322F 2AA198])
      CATPPUCCIN_LATTE = palette("catppuccin-latte", "Catppuccin Latte", %w[EFF1F5 8839EF 1E66F5 4C4F69 9CA0B0 CCD0DA 8839EF 40A02B DF8E1D D20F39 04A5E5])
      GITHUB_LIGHT     = palette("github-light", "GitHub Light", %w[FFFFFF 0969DA 8250DF 1F2328 656D76 D0D7DE 0969DA 1A7F37 9A6700 CF222E 0969DA])
      ROSE_PINE_DAWN   = palette("rose-pine-dawn", "Rose Pine Dawn", %w[FAF4ED D7827E 907AA9 575279 9893A5 F2E9E1 D7827E 56949F EA9D34 B4637A 286983])
      NIGHT_OWL        = palette("night-owl", "Night Owl", %w[011627 82AAFF C792EA D6DEEB 637777 1D3B53 82AAFF 22DA6E ECC48D EF5350 21C7A8])
      MATERIAL_OCEAN   = palette("material-ocean", "Material Ocean", %w[0F111A 84FFFF C792EA 8F93A2 464B5D 1A1C25 84FFFF C3E88D FFCB6B F07178 89DDFF])
      HORIZON          = palette("horizon", "Horizon", %w[1C1E26 E95678 B877DB D5D8DA 6C6F93 2E303E E95678 29D398 FAB795 EC6A88 26BBD9])
      ICEBERG          = palette("iceberg", "Iceberg", %w[161821 84A0C6 A093C7 C6C8D1 6B7089 2E313F 84A0C6 B4BE82 E2A478 E27878 89B8C2])
      MOONFLY          = palette("moonfly", "Moonfly", %w[080808 80A0FF CF87E8 BDBDBD 808080 323437 80A0FF 8CC85F E3C78A FF5189 79DAC8])
      SYNTHWAVE_84     = palette("synthwave-84", "Synthwave '84", %w[262335 FF7EDB 36F9F6 FFFFFF 848BBD 495495 FF7EDB 72F1B8 FEDE5D FE4450 03EDF9])
      MATRIX           = palette("matrix", "Matrix", %w[050B05 00FF41 00CC33 D8FFD8 397D39 0F3D0F 00FF41 00FF41 CFFF04 FF3B30 39FF14])
      ZENBURN          = palette("zenburn", "Zenburn", %w[3F3F3F DCA3A3 8CD0D3 DCDCCC 7F9F7F 5F5F5F DCA3A3 7F9F7F F0DFAF CC9393 8CD0D3])
      # The one palette that keeps a solid selection bar. `mono` is the
      # fallback for terminals that may only have the 16 ANSI colours, where
      # "dark grey" is whatever the terminal decided it is -- on the ones that
      # render it as plain black a tinted bar would vanish, taking the only
      # sign of which row is selected with it. Reversed white-on-black is the
      # look that survives everywhere, so this palette keeps it.
      MONO = new("mono", "Mono (TTY-safe)", CryTUI::Color::RESET, CryTUI::Color::WHITE, CryTUI::Color::GRAY, CryTUI::Color::WHITE, CryTUI::Color::DARK_GRAY, CryTUI::Color::DARK_GRAY, CryTUI::Color::WHITE, CryTUI::Color::GREEN, CryTUI::Color::YELLOW, CryTUI::Color::RED, CryTUI::Color::CYAN, CryTUI::Color::WHITE, CryTUI::Color::BLACK)

      # Near-black grounds under a vibrant two-colour gradient. The header
      # title, the panel headings and the splash all blend `accent` into
      # `accent_alt`, so in this group those two are picked to travel across a
      # hue -- violet into toxic green, orange into gold -- rather than to
      # shade one. The background is kept close to black so the gradient is the
      # only bright thing on the screen, and `success`/`warning`/`danger`/`info`
      # stay recognisably green/amber/red/blue even where the gradient sits on
      # top of those hues, because the status dots are read by colour alone.
      TOXIC_VIOLET = palette("toxic-violet", "Toxic Violet", %w[0A0713 A855F7 7CFF3D EDE4FF 7A6B99 2B2046 A855F7 5CFF8F FFC53D FF3B6B 4DD8FF])
      EMBER_RIOT   = palette("ember-riot", "Ember Riot", %w[100705 FF5A1F FFC93C FFECDF 9C7460 3D2114 FF5A1F 5FE08A FFB020 FF3131 5CC8FF])
      ACID_RAIN    = palette("acid-rain", "Acid Rain", %w[040B08 A6FF00 00E5C0 E4FFF2 5F8A79 143028 A6FF00 66FF8F E8E24D FF4D5E 4DE8FF])
      NEON_CRIMSON = palette("neon-crimson", "Neon Crimson", %w[0D0509 FF1744 FF4FC3 FFE4EE 96667E 3A1226 FF1744 4DE88A FFB13D FF1744 6BB8FF])
      PLASMA_DRIFT = palette("plasma-drift", "Plasma Drift", %w[0B0710 FF3DCB FFA23A FFE6F7 8E6E93 331F3D FF3DCB 5FE8A8 FFA23A FF3355 7AA8FF])
      ULTRAVIOLET  = palette("ultraviolet", "Ultraviolet", %w[06070F 7C4DFF 22E4FF E6EAFF 6B7099 1E2145 7C4DFF 4DFFA8 FFD24D FF4D7A 22E4FF])
      RADIOACTIVE  = palette("radioactive", "Radioactive", %w[070A04 39FF14 FFF34D E8FFDC 6E8A5C 1C2E14 39FF14 39FF14 FFF34D FF3D2E 4DE0FF])
      BLOOD_ORANGE = palette("blood-orange", "Blood Orange", %w[0F0604 FF2E3C FF9A1F FFE8E0 9E6B5E 3B1A14 FF2E3C 66DD8A FF9A1F FF2E3C 5FB8FF])
      HYPERDRIVE   = palette("hyperdrive", "Hyperdrive", %w[04080E 00F0FF FF5FD2 E0F7FF 5F8299 12303D 00F0FF 4DFFB0 FFD24D FF476F 00F0FF])
      NIGHTSHADE   = palette("nightshade", "Nightshade", %w[090614 8B5CFF 00FFA3 E9E4FF 6E6699 241E47 8B5CFF 00FFA3 FFCF4D FF4D6E 5FB0FF])
      MAGMA_CORE   = palette("magma-core", "Magma Core", %w[0D0503 FF6A00 FF1E56 FFE9DC 9E6E52 3D1C0D FF6A00 5FE08A FFB800 FF1E56 5FA8FF])
      DUSK_RIOT    = palette("dusk-riot", "Dusk Riot", %w[0B0610 9D4EDD FF7A00 F2E6FF 7E6690 2E1C3D 9D4EDD 5FE8A0 FF7A00 FF3D6B 6BC5FF])

      # The obsctl-rs catalog, in its order. A config written against the Rust
      # build has to keep resolving to the same palette, so nothing here is
      # reordered or renamed -- new palettes go in `VIVID`.
      REFERENCE = [EMBER, SLATE, BTOP, NORD, DRACULA, GRUVBOX, SOLARIZED_DARK, MONOKAI, ONE_DARK, TOKYO_NIGHT, CATPPUCCIN_MOCHA, ROSE_PINE, KANAGAWA_WAVE, EVERFOREST_DARK, AYU_MIRAGE, GITHUB_DARK, SOLARIZED_LIGHT, CATPPUCCIN_LATTE, GITHUB_LIGHT, ROSE_PINE_DAWN, NIGHT_OWL, MATERIAL_OCEAN, HORIZON, ICEBERG, MOONFLY, SYNTHWAVE_84, MATRIX, ZENBURN]

      VIVID = [TOXIC_VIOLET, EMBER_RIOT, ACID_RAIN, NEON_CRIMSON, PLASMA_DRIFT, ULTRAVIOLET, RADIOACTIVE, BLOOD_ORANGE, HYPERDRIVE, NIGHTSHADE, MAGMA_CORE, DUSK_RIOT]

      # `mono` closes the picker rather than sitting in the middle of it: it is
      # what a terminal without colour falls back to, not a palette anyone
      # scrolls looking for.
      ALL = REFERENCE + VIVID + [MONO]

      # Theme ids that were renamed, kept resolvable so an existing
      # config.yml naming the old id still selects the same palette.
      RENAMED_IDS = {
        "claude" => "ember",
        "codex"  => "slate",
      }

      def self.default : Theme
        EMBER
      end

      def self.by_id(id : String) : Theme
        wanted = id.downcase
        return default if wanted == "default"

        wanted = RENAMED_IDS[wanted]? || wanted
        ALL.find { |theme| theme.id == wanted } || default
      end

      def self.resolve(id : String, custom : CustomThemeSpec? = nil) : Theme
        id.downcase == "custom" ? from_custom(custom || CustomThemeSpec.new) : by_id(id)
      end

      def self.from_custom(spec : CustomThemeSpec) : Theme
        base = default
        # Resolved first because the highlight pair is derived from them, the
        # same way a built-in palette derives it. Someone who sets `bg` and
        # `accent` and nothing else gets a selection bar tinted from *their*
        # two colours rather than one inherited from the default palette --
        # and `highlight_bg`/`highlight_fg` still win when they are spelled
        # out, because an explicit colour is a decision, not a default.
        background = pick(spec.background, base.background)
        accent = pick(spec.accent, base.accent)
        foreground = pick(spec.foreground, base.foreground)
        new(
          "custom", "Custom",
          background, accent,
          pick(spec.accent_alt, base.accent_alt), foreground,
          pick(spec.muted, base.muted), pick(spec.border, base.border),
          pick(spec.border_focus, base.border_focus), pick(spec.success, base.success),
          pick(spec.warning, base.warning), pick(spec.danger, base.danger),
          pick(spec.info, base.info), pick(spec.highlight_background, tint(accent, background)),
          pick(spec.highlight_foreground, foreground)
        )
      end

      def self.parse_hex(value : String) : CryTUI::Color?
        hex = value.lstrip('#')
        return unless hex.matches?(/\A[0-9a-fA-F]{6}\z/)
        CryTUI::Color.rgb(hex[0, 2].to_i(16), hex[2, 2].to_i(16), hex[4, 2].to_i(16))
      end

      # The eleven colours a palette spells out, in order: background, accent,
      # accent_alt, foreground, muted, border, border_focus, success, warning,
      # danger, info.
      #
      # The highlight pair is not among them, because it is not an independent
      # choice: the selection bar is the accent tinted into the background, and
      # the text on it is the ordinary foreground. Deriving both means a
      # palette cannot end up with a selection bar that disagrees with the
      # colours around it, and it means the tint is defined once instead of
      # forty times.
      private def self.palette(id : String, label : String, colors : Array(String)) : Theme
        parsed = colors.map { |color| parse_hex(color) || raise "invalid built-in theme color: #{color}" }
        background, accent, foreground = parsed[0], parsed[1], parsed[3]
        new(
          id, label,
          background, accent, parsed[2], foreground, parsed[4], parsed[5], parsed[6],
          parsed[7], parsed[8], parsed[9], parsed[10], tint(accent, background), foreground
        )
      end

      # `color` composited over `background` at `HIGHLIGHT_TINT` opacity --
      # channel by channel, which is what alpha blending two opaque colours
      # comes down to. Example: an accent of #D97757 over a #1B1916 ground
      # gives #503328 -- a dark warm brown that still reads as "the orange one".
      #
      # Indexed and reset colours have no channels to mix, so they come back
      # untouched: the `mono` palette and any terminal running without truecolour
      # keep whatever they were given.
      private def self.tint(color : CryTUI::Color, background : CryTUI::Color) : CryTUI::Color
        return color unless color.kind.rgb? && background.kind.rgb?

        CryTUI::Color.rgb(
          mix_channel(color.red, background.red),
          mix_channel(color.green, background.green),
          mix_channel(color.blue, background.blue)
        )
      end

      private def self.mix_channel(color : UInt8, background : UInt8) : Int32
        (color.to_f64 * HIGHLIGHT_TINT + background.to_f64 * (1.0 - HIGHLIGHT_TINT)).round.to_i
      end

      private def self.pick(value : String?, fallback : CryTUI::Color) : CryTUI::Color
        value.try { |color| parse_hex(color) } || fallback
      end
    end
  end
end
