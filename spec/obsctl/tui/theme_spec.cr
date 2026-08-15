require "../../spec_helper"
require "../../../src/obsctl/tui/theme"

# How far apart two colours sit on the colour wheel, in degrees. Hue rather
# than raw RGB distance, because what makes a gradient read as a gradient --
# and two status dots read as two states -- is the change in hue, not the
# change in brightness.
private def hue_gap(left : CryTUI::Color, right : CryTUI::Color) : Float64
  difference = (hue(left) - hue(right)).abs
  difference > 180.0 ? 360.0 - difference : difference
end

# WCAG contrast ratio, 1 (identical) to 21 (black on white).
private def contrast(left : CryTUI::Color, right : CryTUI::Color) : Float64
  luminances = {relative_luminance(left), relative_luminance(right)}
  (luminances.max + 0.05) / (luminances.min + 0.05)
end

# The selection bar a palette should have: `accent` mixed into `background` at
# HIGHLIGHT_TINT, recomputed here rather than read back from the theme, so the
# assertion pins the derivation instead of restating it.
private def expected_tint(accent : CryTUI::Color, background : CryTUI::Color) : CryTUI::Color
  ratio = Obsctl::TUI::Theme::HIGHLIGHT_TINT
  channel = ->(color : UInt8, ground : UInt8) do
    (color.to_f64 * ratio + ground.to_f64 * (1.0 - ratio)).round.to_i
  end
  CryTUI::Color.rgb(
    channel.call(accent.red, background.red),
    channel.call(accent.green, background.green),
    channel.call(accent.blue, background.blue)
  )
end

private def relative_luminance(color : CryTUI::Color) : Float64
  channels = [color.red, color.green, color.blue].map do |raw|
    value = raw.to_f64 / 255.0
    value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
  end
  0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
end

private def hue(color : CryTUI::Color) : Float64
  red = color.red.to_f64 / 255.0
  green = color.green.to_f64 / 255.0
  blue = color.blue.to_f64 / 255.0
  range = {red, green, blue}.max - {red, green, blue}.min
  return 0.0 if range.zero?

  degrees = case {red, green, blue}.max
            when red   then 60.0 * (((green - blue) / range) % 6.0)
            when green then 60.0 * ((blue - red) / range + 2.0)
            else            60.0 * ((red - green) / range + 4.0)
            end
  degrees < 0.0 ? degrees + 360.0 : degrees
end

describe Obsctl::TUI::Theme do
  it "maps the TTY-safe palette to Ratatui ANSI colors" do
    theme = Obsctl::TUI::Theme::MONO
    theme.accent.should eq(CryTUI::Color.indexed(15))
    theme.accent_alt.should eq(CryTUI::Color.indexed(7))
    theme.muted.should eq(CryTUI::Color.indexed(8))
  end

  it "exposes the complete Rust reference theme catalog in reference order" do
    reference = Obsctl::TUI::Theme::REFERENCE
    reference.size.should eq(28)
    reference.first.id.should eq("ember")
    reference[1].id.should eq("slate")
    reference.last.id.should eq("zenburn")

    # The reference catalog still opens the picker, in its own order, so a
    # config written against the Rust build lands on the same palette.
    themes = Obsctl::TUI::Theme::ALL
    themes.first(reference.size).map(&.id).should eq(reference.map(&.id))
    themes.size.should eq(reference.size + Obsctl::TUI::Theme::VIVID.size + 1)
    themes.last.id.should eq("mono")
    themes.map(&.id).uniq!.size.should eq(themes.size)
  end

  it "gives every vivid palette a dark ground and a gradient that changes hue" do
    Obsctl::TUI::Theme::VIVID.size.should be >= 10

    Obsctl::TUI::Theme::VIVID.each do |theme|
      # Near-black, so the gradient is the brightest thing on the screen.
      brightness = theme.background.red.to_i + theme.background.green.to_i + theme.background.blue.to_i
      brightness.should be < 60

      # A loud gradient is no excuse for uncomfortable copy. These floors sit
      # above every palette in the reference catalog, which is the point: a
      # ground this dark is what buys the headroom, so spend it.
      contrast(theme.foreground, theme.background).should be > 12.0
      contrast(theme.muted, theme.background).should be > 3.5

      # `accent` blends into `accent_alt` across the header and panel titles.
      # A pair that only differs in shade renders as a flat title, so the two
      # have to sit on different hues. 20 degrees is the floor, not the target:
      # the warm pairs (orange into gold) sit near it, the violet-into-green
      # pairs are most of a colour wheel apart.
      hue_gap(theme.accent, theme.accent_alt).should be > 20

      # The status dots are read by colour alone, whatever the gradient does.
      [theme.success, theme.warning, theme.danger, theme.info].each_combination(2) do |pair|
        hue_gap(pair[0], pair[1]).should be > 20
      end
    end
  end

  # A selection bar used to be a solid slab of `accent` with the row's own
  # text left on top of it, which put muted grey on bright cyan often enough
  # to be a readability bug rather than a taste one. It is now the accent
  # mixed into the background, so the bar marks the row without repainting it.
  it "tints every selection bar into the theme background instead of filling it" do
    (Obsctl::TUI::Theme::ALL - [Obsctl::TUI::Theme::MONO]).each do |theme|
      # The bar is exactly the accent mixed into the background at
      # HIGHLIGHT_TINT, checked channel by channel against the mix recomputed
      # here.
      #
      # This replaces an earlier assertion that the bar was "nearer the ground
      # than the accent", which could not fail for any tint below 0.5 no matter
      # what the colours were -- it reduced to `T < 1 - T` and said nothing
      # about the palette. Recomputing the mix pins both the ratio and the
      # derivation, and would catch a palette that spelled its bar out by hand.
      theme.highlight_background.should eq(expected_tint(theme.accent, theme.background))

      # Visibly a different colour from the ground, or nothing marks the
      # selected row at all.
      #
      # 1.2 is not a standard, and there is no WCAG number for "a wash behind a
      # row"; it is the honest floor of this palette set. rose-pine-dawn sits
      # at 1.28 and eleven other palettes are under 1.5, all of them light
      # ones, where the accent is darker than the ground and a 28% mix moves it
      # very little. Raising HIGHLIGHT_TINT would separate those bars and cost
      # text legibility on the dark palettes in exchange -- measured across the
      # set, a tint of 0.4 lifts the worst bar to 1.43 but drops
      # material-ocean's text-on-bar from 2.70 to 1.81. The trade was left
      # where it is deliberately; this records where "here" actually is.
      contrast(theme.highlight_background, theme.background).should be > 1.2

      # Text on the bar. A span whose own colour cannot be read there is
      # swapped for `highlight_foreground` by `CryTUI::ForegroundGuard`, so
      # this pair is the floor for everything the selected row can show.
      #
      # 2.5 is below WCAG AA for body text, which is 4.5, and below the 3:1
      # large-text floor too. Five palettes are under 4.5 -- material-ocean
      # 2.70, solarized-light 3.00, solarized-dark 3.80, one-dark 3.87,
      # everforest-dark 4.18 -- so a higher threshold here would fail the set
      # rather than describe it. Named for what it is: a regression floor, not
      # a standard met.
      contrast(theme.highlight_foreground, theme.highlight_background).should be > 2.5
    end
  end

  # The count badge in a panel title is a small inverse chip. It shares no
  # colours with the selection bar, which is a dim wash and wants the opposite
  # treatment -- when the two were one pair, dimming the bar erased the badge.
  it "keeps the count badge reading as a chip against the panel ground" do
    (Obsctl::TUI::Theme::ALL - [Obsctl::TUI::Theme::MONO]).each do |theme|
      # One measurement covers both things that matter, because the badge is
      # the panel's own background painted on the accent: the same ratio says
      # the chip separates from the panel behind it and that its digits read on
      # the chip. (Contrast is symmetric, so asserting it in both directions
      # would only be the same number twice.)
      #
      # 3:1 is the WCAG floor for a non-text element, and every palette clears
      # it except rose-pine-dawn at 2.60 -- upstream Rosé Pine Dawn's rose
      # (#D7827E) really is that close in luminance to its cream ground, so
      # this is the palette reproduced faithfully rather than a mistake to fix
      # here. The threshold names that floor rather than claiming a limit the
      # set does not meet.
      contrast(theme.badge_foreground, theme.badge_background).should be > 2.5
    end
  end

  # `mono` is the palette for terminals that may have 16 colours and their own
  # opinion about what "dark grey" means. A tint there could come out
  # indistinguishable from the background, so it keeps the reversed bar.
  it "leaves the TTY-safe palette with a solid reversed selection bar" do
    Obsctl::TUI::Theme::MONO.highlight_background.should eq(CryTUI::Color::WHITE)
    Obsctl::TUI::Theme::MONO.highlight_foreground.should eq(CryTUI::Color::BLACK)
  end

  it "resolves names case-insensitively and defaults unknown names" do
    Obsctl::TUI::Theme.by_id("TOKYO-NIGHT").should eq(Obsctl::TUI::Theme::TOKYO_NIGHT)
    Obsctl::TUI::Theme.by_id("missing").should eq(Obsctl::TUI::Theme.default)
  end

  # `claude` and `codex` were renamed. A config written before the rename must
  # keep selecting the same palette rather than silently falling back.
  it "still resolves renamed theme ids to their palette" do
    Obsctl::TUI::Theme.by_id("claude").should eq(Obsctl::TUI::Theme::EMBER)
    Obsctl::TUI::Theme.by_id("codex").should eq(Obsctl::TUI::Theme::SLATE)
    Obsctl::TUI::Theme.by_id("CLAUDE").should eq(Obsctl::TUI::Theme::EMBER)
  end

  it "keeps every renamed id pointing at a palette that exists" do
    Obsctl::TUI::Theme::RENAMED_IDS.each_value do |new_id|
      Obsctl::TUI::Theme::ALL.map(&.id).should contain(new_id)
    end
  end

  it "overlays valid custom colors and falls back per invalid field" do
    custom = Obsctl::TUI::Theme.from_custom(Obsctl::TUI::CustomThemeSpec.new(
      background: "#010203",
      accent: "invalid"
    ))
    custom.background.should eq(CryTUI::Color.rgb(1, 2, 3))
    custom.accent.should eq(Obsctl::TUI::Theme.default.accent)
  end

  it "picks selection-bar text that reads on a hand-picked bar colour" do
    # `highlight_bg` and `highlight_fg` are two halves of one decision, and a
    # user may set only the first. Ember's near-white `fg` on a bright rose bar
    # reads at 2.60; its near-black `bg` reads at 5.62 on the same colour.
    custom = Obsctl::TUI::Theme.from_custom(Obsctl::TUI::CustomThemeSpec.new(highlight_background: "#D97757"))

    custom.highlight_foreground.should eq(Obsctl::TUI::Theme.default.background)
    contrast(custom.highlight_foreground, custom.highlight_background).should be > 4.5
  end

  it "leaves an explicit selection-bar text colour alone" do
    # Measuring is a fallback for a decision the user did not make, never an
    # override of one they did.
    custom = Obsctl::TUI::Theme.from_custom(Obsctl::TUI::CustomThemeSpec.new(
      highlight_background: "#D97757",
      highlight_foreground: "#FFFFFF"
    ))

    custom.highlight_foreground.should eq(CryTUI::Color.rgb(255, 255, 255))
  end

  it "keeps deriving the bar from the user's own colours when neither is set" do
    custom = Obsctl::TUI::Theme.from_custom(Obsctl::TUI::CustomThemeSpec.new(
      background: "#000000",
      accent: "#00FF00"
    ))

    custom.highlight_background.should eq(expected_tint(custom.accent, custom.background))
  end
end
