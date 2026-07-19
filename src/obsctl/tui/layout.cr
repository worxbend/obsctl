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
        vertical = overlap(CryTUI::Layout.new(
          CryTUI::Direction::Vertical,
          [CryTUI::Constraint.length(4), CryTUI::Constraint.length(4), CryTUI::Constraint.min(6), CryTUI::Constraint.length(7), CryTUI::Constraint.length(4)]
        ).split(area), CryTUI::Direction::Vertical)
        middle_rows = overlap(CryTUI::Layout.new(
          CryTUI::Direction::Vertical,
          [CryTUI::Constraint.min(8), CryTUI::Constraint.length(7)]
        ).split(vertical[2]), CryTUI::Direction::Vertical)
        upper = overlap(CryTUI::Layout.new(constraints: [CryTUI::Constraint.percentage(50), CryTUI::Constraint.percentage(50)]).split(middle_rows[0]), CryTUI::Direction::Horizontal)
        lower = overlap(CryTUI::Layout.new(constraints: [CryTUI::Constraint.percentage(50), CryTUI::Constraint.percentage(50)]).split(middle_rows[1]), CryTUI::Direction::Horizontal)
        LayoutAreas.new(vertical[0], vertical[1], upper[0], upper[1], lower[0], lower[1], vertical[3], vertical[4])
      end

      # Preserve the normal layout's outer extent while sharing one border cell
      # at each internal boundary. Shifting later rectangles without extending
      # them would leave an uncovered cell at the far edge.
      private def overlap(areas : Array(CryTUI::Rect), direction : CryTUI::Direction) : Array(CryTUI::Rect)
        areas.map_with_index do |rect, index|
          next rect if index == 0 || rect.empty?
          if direction.horizontal?
            CryTUI::Rect.new(rect.x - 1, rect.y, rect.width + 1, rect.height)
          else
            CryTUI::Rect.new(rect.x, rect.y - 1, rect.width, rect.height + 1)
          end
        end
      end
    end
  end
end
