require "../spec_helper"
require "../../src/crytui"

describe CryTUI::Line do
  it "renders styled spans with Unicode-aware alignment" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 10, 1))
    red = CryTUI::Style.new(foreground: CryTUI::Color::RED)
    blue = CryTUI::Style.new(foreground: CryTUI::Color::BLUE)
    line = CryTUI::Line.new([
      CryTUI::Span.new("界", red),
      CryTUI::Span.new(" ok", blue),
    ], CryTUI::Alignment::Center)
    line.render(buffer, buffer.area)

    buffer[2, 0].symbol.should eq("界")
    buffer[2, 0].style.should eq(red)
    buffer[4, 0].symbol.should eq(" ")
    buffer[5, 0].style.should eq(blue)
  end
end

describe CryTUI::Widgets::List do
  it "scrolls selected variable-height items into view and highlights full rows" do
    items = [
      CryTUI::Widgets::ListItem.from("one"),
      CryTUI::Widgets::ListItem.new([CryTUI::Line.from("two"), CryTUI::Line.from("meter")]),
      CryTUI::Widgets::ListItem.from("three"),
    ]
    selected = CryTUI::Style.new(background: CryTUI::Color::BLUE)
    state = CryTUI::Widgets::ListState.new(selected: 2)
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 8, 3))
    CryTUI::Widgets::List.new(items, highlight_style: selected).render(buffer.area, buffer, state)

    state.offset.should eq(1)
    buffer.lines.should eq(["two     ", "meter   ", "three   "])
    buffer[7, 2].style.background.should eq(CryTUI::Color::BLUE)
  end
end
