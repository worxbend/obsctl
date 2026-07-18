require "../../crytui"

module Obsctl
  module TUI
    record LayoutAreas,
      header : CryTUI::Rect,
      live_bar : CryTUI::Rect,
      scenes : CryTUI::Rect,
      audio : CryTUI::Rect,
      profiles : CryTUI::Rect,
      collections : CryTUI::Rect,
      logs : CryTUI::Rect,
      palette : CryTUI::Rect

    module DashboardLayout
      extend self

      def compute(area : CryTUI::Rect) : LayoutAreas
        vertical = CryTUI::Layout.new(
          CryTUI::Direction::Vertical,
          [CryTUI::Constraint.length(4), CryTUI::Constraint.length(4), CryTUI::Constraint.min(6), CryTUI::Constraint.length(7), CryTUI::Constraint.length(4)]
        ).split(area)
        middle_rows = CryTUI::Layout.new(
          CryTUI::Direction::Vertical,
          [CryTUI::Constraint.min(8), CryTUI::Constraint.length(7)]
        ).split(vertical[2])
        upper = CryTUI::Layout.new(constraints: [CryTUI::Constraint.percentage(50), CryTUI::Constraint.percentage(50)]).split(middle_rows[0])
        lower = CryTUI::Layout.new(constraints: [CryTUI::Constraint.percentage(50), CryTUI::Constraint.percentage(50)]).split(middle_rows[1])
        LayoutAreas.new(vertical[0], vertical[1], upper[0], upper[1], lower[0], lower[1], vertical[3], vertical[4])
      end
    end
  end
end
