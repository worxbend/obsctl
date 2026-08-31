require "../spec_helper"
require "../../src/crytui"

# Renders the list into a buffer the size of the content box and reads the
# text back row by row, so each example can compare `row_at`'s answer against
# what was actually drawn rather than against a second hand-written walk.
private def drawn_rows(items : Array(CryTUI::Widgets::ListItem), selected : Int32?, content : CryTUI::Rect) : Array(String)
  buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, content.right, content.bottom))
  state = CryTUI::Widgets::ListState.new(selected: selected)
  CryTUI::Widgets::List.new(items).render(content, buffer, state)
  buffer.lines[content.y...content.bottom].map(&.rstrip)
end

describe CryTUI::Widgets::List do
  describe ".row_at" do
    it "names the item render drew on every row, scrolling included" do
      # Ten rows into a box that fits four, with the eighth selected: the list
      # has to scroll to reach the selection, so the top row on screen is item
      # 4 and a hit test that started counting at item 0 would be four out.
      items = (0...10).map { |index| CryTUI::Widgets::ListItem.from("item-#{index}") }
      content = CryTUI::Rect.new(0, 3, 12, 4)

      drawn_rows(items, 7, content).each_with_index do |text, offset|
        row = content.y + offset
        index = CryTUI::Widgets::List.row_at(items.size, 7, content, row)
        index.should_not be_nil
        text.should eq("item-#{index}")
      end

      CryTUI::Widgets::List.row_at(items.size, 7, content, content.y).should eq(4)
    end

    it "follows the per-item heights when rows are taller than one line" do
      items = [
        CryTUI::Widgets::ListItem.new([CryTUI::Line.from("a-top"), CryTUI::Line.from("a-bottom")]),
        CryTUI::Widgets::ListItem.new([CryTUI::Line.from("b-only")]),
        CryTUI::Widgets::ListItem.new([CryTUI::Line.from("c-top"), CryTUI::Line.from("c-bottom")]),
      ]
      content = CryTUI::Rect.new(0, 0, 12, 5)
      heights = items.map(&.height)

      drawn_rows(items, 0, content).should eq(["a-top", "a-bottom", "b-only", "c-top", "c-bottom"])
      (0...5).map { |row| CryTUI::Widgets::List.row_at(heights, 0, content, row) }.should eq([0, 0, 1, 2, 2])
    end

    it "has no item past the last one, outside the box, or in an empty list" do
      items = [CryTUI::Widgets::ListItem.from("one"), CryTUI::Widgets::ListItem.from("two")]
      content = CryTUI::Rect.new(0, 1, 12, 5)

      # Three rows of the box are left over once both items are drawn.
      drawn_rows(items, 0, content).should eq(["one", "two", "", "", ""])

      CryTUI::Widgets::List.row_at(items.size, 0, content, content.y + 2).should be_nil
      CryTUI::Widgets::List.row_at(items.size, 0, content, content.y - 1).should be_nil
      CryTUI::Widgets::List.row_at(items.size, 0, content, content.bottom).should be_nil
      CryTUI::Widgets::List.row_at(0, nil, content, content.y).should be_nil
    end
  end
end
