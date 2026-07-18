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

  it "matches Ratatui for ambiguous TUI symbols and emoji presentation" do
    CryTUI::TextWidth.width("▶◇🎚⚠✓").should eq(5)
    CryTUI::TextWidth.width("⚡🔊").should eq(4)
    CryTUI::TextWidth.width("▶️").should eq(2)
  end
end
