require "../../spec_helper"
require "../../../src/obsctl/tui/theme"

describe Obsctl::TUI::Theme do
  it "maps the TTY-safe palette to Ratatui ANSI colors" do
    theme = Obsctl::TUI::Theme::MONO
    theme.accent.should eq(CryTUI::Color.indexed(15))
    theme.accent_alt.should eq(CryTUI::Color.indexed(7))
    theme.muted.should eq(CryTUI::Color.indexed(8))
  end

  it "exposes the complete Rust reference theme catalog in reference order" do
    themes = Obsctl::TUI::Theme::ALL
    themes.size.should eq(29)
    themes.first.id.should eq("ember")
    themes[1].id.should eq("slate")
    themes.last.id.should eq("mono")
    themes.map(&.id).uniq!.size.should eq(themes.size)
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
