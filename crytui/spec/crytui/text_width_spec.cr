require "../spec_helper"
require "../../src/crytui"

describe CryTUI::TextWidth do
  it "measures ASCII, Cyrillic, combining text, CJK, and emoji" do
    CryTUI::TextWidth.width("buffer").should eq(6)
    CryTUI::TextWidth.width("Київ").should eq(4)
    CryTUI::TextWidth.width("e\u0301").should eq(1)
    CryTUI::TextWidth.width("界").should eq(2)
    CryTUI::TextWidth.width("👩‍💻").should eq(2)
    CryTUI::TextWidth.width("🇺🇦").should eq(2)
  end

  it "keeps BMP presentation-ambiguous symbols narrow" do
    # ▶ ◇ ⚠ ✓ have narrow text glyphs, so terminals render them one cell wide.
    CryTUI::TextWidth.width("▶◇⚠✓").should eq(4)
    CryTUI::TextWidth.width("▶️").should eq(2) # VS16 forces emoji presentation
  end

  it "reserves two cells for supplementary-plane pictographs" do
    # 🎚 🎛 🗂 are Emoji_Presentation=No, but the astral plane has no narrow
    # text glyph, so every terminal renders them two cells wide. Under-counting
    # them shifts each panel's right border one column right.
    CryTUI::TextWidth.width("🎚").should eq(2)
    CryTUI::TextWidth.width("🎛").should eq(2)
    CryTUI::TextWidth.width("🗂").should eq(2)
    CryTUI::TextWidth.width("⚡🔊").should eq(4)
  end

  it "fits text to a column count from either end" do
    CryTUI::TextWidth.truncate("buffer", 6, "…").should eq("buffer")
    CryTUI::TextWidth.truncate("buffer", 4, "…").should eq("buf…")
    CryTUI::TextWidth.truncate_start("buffer", 4, "…").should eq("…fer")
    # No ellipsis asked for, so every column goes to the text itself.
    CryTUI::TextWidth.truncate("buffer", 3).should eq("buf")
    CryTUI::TextWidth.truncate_start("buffer", 3).should eq("fer")
  end

  it "drops a two-column glyph whole rather than drawing half of it" do
    # Half a wide glyph is not a thing a terminal can draw: keeping one column
    # of it would push everything after it a column right.
    CryTUI::TextWidth.width(CryTUI::TextWidth.truncate("界界界", 5, "")).should eq(4)
    CryTUI::TextWidth.width(CryTUI::TextWidth.truncate_start("界界界", 5, "")).should eq(4)
    # Three columns hold one wide glyph and the ellipsis, not one and a half.
    CryTUI::TextWidth.truncate("界界界", 3, "…").should eq("界…")
    CryTUI::TextWidth.truncate_start("界界界", 3, "…").should eq("…界")
  end

  it "cuts an ellipsis that is itself too long for the space" do
    CryTUI::TextWidth.truncate("buffer", 1, "..").should eq(".")
    CryTUI::TextWidth.truncate_start("buffer", 0, "…").should eq("")
  end
end
