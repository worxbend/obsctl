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
end
