require "../spec_helper"
require "../../src/crytui"

describe CryTUI::Rect do
  it "clips intersections and inner margins" do
    area = CryTUI::Rect.new(2, 3, 10, 8)
    area.inner(2).should eq(CryTUI::Rect.new(4, 5, 6, 4))
    area.intersection(CryTUI::Rect.new(8, 0, 10, 6)).should eq(CryTUI::Rect.new(8, 3, 4, 3))
  end
end

describe CryTUI::Layout do
  it "recreates the obsctl dashboard fixed and flexible rows" do
    rows = CryTUI::Layout.new(
      CryTUI::Direction::Vertical,
      [CryTUI::Constraint.length(4), CryTUI::Constraint.length(4), CryTUI::Constraint.min(6), CryTUI::Constraint.length(7), CryTUI::Constraint.length(4)]
    ).split(CryTUI::Rect.new(0, 0, 100, 40))

    rows.map(&.height).should eq([4, 4, 21, 7, 4])
    rows.map(&.y).should eq([0, 4, 8, 29, 36])
  end

  it "splits percentage columns without exceeding the area" do
    columns = CryTUI::Layout.new(
      constraints: [CryTUI::Constraint.percentage(50), CryTUI::Constraint.percentage(50)]
    ).split(CryTUI::Rect.new(3, 2, 81, 5))

    columns.map(&.width).should eq([40, 40])
    columns.map(&.x).should eq([3, 43])
  end
end
