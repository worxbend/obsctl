require "../spec_helper"
require "../../src/crytui"

describe CryTUI::TextWidth do
  it "measures ASCII, Cyrillic, combining text, CJK, and emoji" do
    CryTUI::TextWidth.width("obsctl").should eq(6)
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
end
