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

  it "places grapheme clusters according to terminal display width" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 8, 1))
    buffer.set_string(0, 0, "A界e\u0301👩‍💻").should eq(6)

    buffer[0, 0].symbol.should eq("A")
    buffer[1, 0].symbol.should eq("界")
    buffer[2, 0].continuation?.should be_true
    buffer[3, 0].symbol.should eq("e\u0301")
    buffer[4, 0].symbol.should eq("👩‍💻")
    buffer[5, 0].continuation?.should be_true
  end

  it "does not split a wide grapheme at the clipping boundary" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 3, 1))
    buffer.set_string(0, 0, "ab界").should eq(2)
    buffer.lines.should eq(["ab "])
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
      "┌Demo──────┐",
      "│hello     │",
      "└──────────┘",
    ])
  end
end

describe CryTUI::Widgets::Block do
  it "renders an unpadded title even when no borders are selected" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 8, 2))
    CryTUI::Widgets::Block.new(title: "Title", borders: CryTUI::Widgets::Borders::None).render(buffer.area, buffer)

    buffer.lines.should eq(["Title   ", "        "])
  end

  it "clips long titles before the right border" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 8, 2))
    CryTUI::Widgets::Block.new(title: "very long title").render(buffer.area, buffer)

    buffer.lines.first.should eq("┌very l┐")
  end

  it "preserves styled spans in line titles" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 10, 3))
    title = CryTUI::Line.new([
      CryTUI::Span.new("A", CryTUI::Style.new(foreground: CryTUI::Color::RED)),
      CryTUI::Span.new("B", CryTUI::Style.new(foreground: CryTUI::Color::BLUE)),
    ])
    CryTUI::Widgets::Block.new(title: title).render(buffer.area, buffer)

    buffer[1, 0].symbol.should eq("A")
    buffer[1, 0].style.foreground.should eq(CryTUI::Color::RED)
    buffer[2, 0].symbol.should eq("B")
    buffer[2, 0].style.foreground.should eq(CryTUI::Color::BLUE)
  end

  it "renders and reserves independent border sides" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 8, 3))
    block = CryTUI::Widgets::Block.new(
      borders: CryTUI::Widgets::Borders::Left,
      border_set: CryTUI::Widgets::BorderSet::THICK
    )
    block.render(buffer.area, buffer)

    buffer.lines.should eq(["┃       ", "┃       ", "┃       "])
    block.inner(buffer.area).should eq(CryTUI::Rect.new(1, 0, 7, 3))
  end

  it "draws corners only where adjacent sides meet" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 6, 3))
    borders = CryTUI::Widgets::Borders::Top | CryTUI::Widgets::Borders::Left
    CryTUI::Widgets::Block.new(borders: borders, border_set: CryTUI::Widgets::BorderSet::ROUNDED).render(buffer.area, buffer)

    buffer.lines.should eq(["╭─────", "│     ", "│     "])
  end
end

describe CryTUI::AnsiBackend do
  it "emits styled cell changes and skips wide-cell continuations" do
    io = IO::Memory.new
    backend = CryTUI::AnsiBackend.new(io, 4, 1, alternate_screen: false)
    terminal = CryTUI::Terminal.new(backend)
    terminal.run do |active|
      active.draw do |frame|
        frame.buffer.set_string(0, 0, "界!", CryTUI::Style.new(foreground: CryTUI::Color.rgb(1, 2, 3), modifiers: CryTUI::Modifier::Bold))
      end
    end

    output = io.to_s
    output.should contain("\e[?25l\e[2J\e[H")
    output.should contain("\e[1;38;2;1;2;3m界")
    output.should contain("\e[1;3H!")
    output.should end_with("\e[0m\e[?25h")
  end

  it "restores terminal state when the render block raises" do
    io = IO::Memory.new
    backend = CryTUI::AnsiBackend.new(io, 2, 1, alternate_screen: true)
    terminal = CryTUI::Terminal.new(backend)

    expect_raises(Exception, "boom") do
      terminal.run { raise "boom" }
    end
    io.to_s.should end_with("\e[0m\e[?25h\e[?1049l")
  end
end
