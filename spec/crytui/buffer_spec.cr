require "../spec_helper"
require "../../src/crytui"

describe CryTUI::Buffer do
  it "writes clipped text and preserves style separately from symbols" do
    red = CryTUI::Style.new(foreground: CryTUI::Color::RED)
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 5, 1))
    buffer.set_string(3, 0, "hello", red).should eq(2)
    buffer.lines.should eq(["   he"])
    buffer[3, 0].style.should eq(red)
  end

  it "reports only changed cells" do
    before = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 4, 1))
    after = before.copy
    after.set_string(1, 0, "x")
    changes = before.diff(after)
    changes.size.should eq(1)
    changes[0][0..1].should eq({1, 0})
  end
end

describe CryTUI::Terminal do
  it "renders frames into a deterministic test backend" do
    backend = CryTUI::TestBackend.new(12, 3)
    terminal = CryTUI::Terminal.new(backend)
    terminal.draw do |frame|
      CryTUI::Widgets::Paragraph.new("hello", block: CryTUI::Widgets::Block.new("Demo")).render(frame.area, frame.buffer)
    end

    backend.buffer.lines.should eq([
      "+- Demo ---+",
      "|hello     |",
      "+----------+",
    ])
  end
end
