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
      palette : CryTUI::Rect,
      stats : CryTUI::Rect? = nil

    module DashboardLayout
      extend self

      # The stats pane takes a fixed column rather than a share of the logs
      # row: log lines want every column they can get, and stream health is
      # the same handful of short rows however wide the terminal is. The wider
      # column is used when the row can spare it, because it is what lets the
      # panel print frame totals and the FPS sparkline instead of bare counts.
      STATS_WIDTH      = 40
      WIDE_STATS_WIDTH = 48
      LOGS_MIN_WIDTH   = 40

      # `stats_pane` is requested by the caller rather than derived here so the
      # layout stays a pure function of the area. It is honoured only when the
      # logs row can spare the column.
      def compute(area : CryTUI::Rect, stats_pane : Bool = false) : LayoutAreas
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
        logs, stats = split_logs_row(vertical[3], stats_pane)
        LayoutAreas.new(vertical[0], vertical[1], upper[0], upper[1], lower[0], lower[1], logs, vertical[4], stats)
      end

      # Splits the logs row into logs and stats, or leaves logs at full width
      # when the row is too narrow to make both readable.
      private def split_logs_row(row : CryTUI::Rect, stats_pane : Bool) : Tuple(CryTUI::Rect, CryTUI::Rect?)
        return {row, nil} unless stats_pane && row.width >= LOGS_MIN_WIDTH + STATS_WIDTH

        width = row.width >= LOGS_MIN_WIDTH + WIDE_STATS_WIDTH ? WIDE_STATS_WIDTH : STATS_WIDTH
        columns = overlap(CryTUI::Layout.new(
          constraints: [CryTUI::Constraint.min(LOGS_MIN_WIDTH), CryTUI::Constraint.length(width)]
        ).split(row), CryTUI::Direction::Horizontal)
        {columns[0], columns[1]}
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
