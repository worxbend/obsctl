require "../../spec_helper"
require "../../../src/obsctl/tui/anim"

describe Obsctl::TUI::Anim do
  it "blends RGB colors and preserves named terminal colors" do
    Obsctl::TUI::Anim.blend(CryTUI::Color.rgb(0, 0, 0), CryTUI::Color.rgb(100, 200, 255), 0.5)
      .should eq(CryTUI::Color.rgb(50, 100, 128))
    Obsctl::TUI::Anim.blend(CryTUI::Color::RED, CryTUI::Color::BLUE, 0.5)
      .should eq(CryTUI::Color::RED)
  end

  it "builds gradients without changing their text" do
    line = Obsctl::TUI::Anim.gradient_line("OBS", CryTUI::Color.rgb(0, 0, 0), CryTUI::Color.rgb(255, 0, 0), 3_u64, true)
    line.spans.map(&.content).join.should eq("OBS")
    line.spans.each { |span| span.style.modifiers.bold?.should be_true }
  end

  it "renders fixed-width Unicode and ASCII histories" do
    Obsctl::TUI::Anim.sparkline([] of Float64, 4).should eq("▁▁▁▁")
    Obsctl::TUI::Anim.sparkline([0.0, 5.0, 10.0], 4).should eq("▁▁▅█")
    Obsctl::TUI::Anim.sparkline_ascii([2.0, 3.0], 4).size.should eq(4)
  end
end

describe Obsctl::TUI::AnimClock do
  it "provides bounded periodic pulses and safe spinners" do
    clock = Obsctl::TUI::AnimClock.new
    start = clock.pulse(8_u64)
    8.times { clock.tick }
    clock.pulse(8_u64).should be_close(start, 0.000001)
    clock.spinner(["a", "b"], 1_u64).should eq("a")
    clock.spinner([] of String).should eq("")
  end
end
