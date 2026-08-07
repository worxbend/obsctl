require "../../crytui"
require "./keymap"
require "./model"

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
      stats : CryTUI::Rect? = nil do
      # The rectangle a focus panel is drawn in, so callers that reason about a
      # panel -- half-page steps, hit tests -- do not repeat the mapping.
      def panel(focus : FocusPanel) : CryTUI::Rect
        case focus
        when .scenes?   then scenes
        when .audio?    then audio
        when .profiles? then profiles
        else                 collections
        end
      end
    end

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

    # The screen rows a channel strip is divided into. A row is nil when the
    # panel is too short to afford it; the meter always survives, because a
    # mixer without meters is not a mixer.
    record MixerRows,
      name : Int32?,
      meter_top : Int32,
      meter_height : Int32,
      decibels : Int32?,
      value : Int32?,
      mute : Int32?

    # The columns inside one strip: a meter, then a fader beside it.
    record MixerColumns,
      meter : Int32,
      meter_width : Int32,
      fader : Int32

    # Where the vertical mixer puts its channel strips.
    #
    # Shared by the widget and the hit test, the same way the dashboard layout
    # is: the strips are a pure function of the area, the input count and the
    # cursor, so a click can be resolved by recomputing them rather than by
    # remembering where the last frame drew them.
    module MixerLayout
      extend self

      STRIP_WIDTH = 8
      GAP         = 1
      METER_WIDTH = 3
      # Meter, a blank column, then the fader.
      CONTENT_WIDTH = METER_WIDTH + 2

      def stride : Int32
        STRIP_WIDTH + GAP
      end

      # Panels are drawn inside a one-cell border on every side.
      def inner(area : CryTUI::Rect) : CryTUI::Rect
        CryTUI::Rect.new(area.x + 1, area.y + 1, {area.width - 2, 0}.max, {area.height - 2, 0}.max)
      end

      # Strips that fit side by side. Always at least one, so a panel too
      # narrow for a whole strip still shows the selected channel clipped
      # rather than nothing at all.
      def capacity(area : CryTUI::Rect) : Int32
        {(inner(area).width + GAP) // stride, 1}.max
      end

      # The first channel drawn. Derived from the cursor rather than stored, so
      # the widget and the hit test cannot disagree about where the strips are.
      def offset(count : Int32, cursor : Int32, area : CryTUI::Rect) : Int32
        room = capacity(area)
        return 0 if count <= room
        cursor = cursor.clamp(0, count - 1)
        start = cursor >= room ? cursor - room + 1 : 0
        start.clamp(0, count - room)
      end

      # `{channel index, strip rectangle}` for every strip on screen, in draw
      # order. A strip that would not fit whole is left out rather than drawn
      # cut in half -- except on a panel too narrow for even one, where the
      # selected channel is clipped so something is still shown.
      def strips(count : Int32, cursor : Int32, area : CryTUI::Rect) : Array(Tuple(Int32, CryTUI::Rect))
        content = inner(area)
        return [] of Tuple(Int32, CryTUI::Rect) if count <= 0 || content.empty?

        first = offset(count, cursor, area)
        room = {capacity(area), count - first}.min
        (0...room).compact_map do |position|
          x = content.x + position * stride
          width = {STRIP_WIDTH, content.right - x}.min
          next if width <= 0
          {first + position, CryTUI::Rect.new(x, content.y, width, content.height)}
        end.to_a
      end

      # The channel under a column, or nil for the gutter between strips.
      def index_at(count : Int32, cursor : Int32, area : CryTUI::Rect, column : Int32) : Int32?
        strips(count, cursor, area).each do |index, rect|
          return index if column >= rect.x && column < rect.right
        end
        nil
      end

      # Rows are given up from the bottom as the panel shrinks: the dB readout
      # goes first, then the gain readout, then the mute badge.
      def rows(area : CryTUI::Rect) : MixerRows
        content = inner(area)
        height = content.height
        name = height >= 2 ? content.y : nil
        mute = height >= 3 ? content.bottom - 1 : nil
        value = height >= 5 ? content.bottom - 2 : nil
        decibels = height >= 7 ? content.bottom - 3 : nil
        top = content.y + (name ? 1 : 0)
        bottom = content.bottom - [mute, value, decibels].count { |row| row }
        MixerRows.new(name, top, {bottom - top, 0}.max, decibels, value, mute)
      end

      def columns(strip : CryTUI::Rect) : MixerColumns
        pad = {(strip.width - CONTENT_WIDTH) // 2, 0}.max
        meter = strip.x + pad
        MixerColumns.new(meter, METER_WIDTH, meter + METER_WIDTH + 1)
      end
    end

    record SettingsAreas, themes : CryTUI::Rect, preview : CryTUI::Rect

    # The appearance lab's two columns, shared by its widget and its hit test so
    # a click lands on the theme the pointer is actually over.
    module SettingsLayout
      extend self

      def compute(area : CryTUI::Rect) : SettingsAreas
        inner = area.inner(1)
        sections = CryTUI::Layout.new(constraints: [CryTUI::Constraint.percentage(45), CryTUI::Constraint.percentage(55)]).split(inner)
        SettingsAreas.new(sections[0], sections[1])
      end
    end

    # Where the palette draws its completion chips. Kept out of the widget so
    # the hit test measures the same columns that were painted.
    module PaletteLayout
      extend self

      MAX_VISIBLE_COMPLETIONS = 8
      # The indent before the first chip and the gap between chips, matching the
      # spans `Widgets::CommandPalette` emits.
      INDENT = 2
      GAP    = 1
      # Completions are the third line of the panel, under the result and the
      # prompt.
      COMPLETION_LINE = 2

      def visible(completions : Array(String)) : Array(String)
        completions.first(MAX_VISIBLE_COMPLETIONS)
      end

      def label(completion : String) : String
        "[#{completion}]"
      end

      def completion_row(area : CryTUI::Rect) : Int32
        area.inner(1).y + COMPLETION_LINE
      end

      # First and last column of each visible chip, in draw order.
      def chips(completions : Array(String), area : CryTUI::Rect) : Array(Tuple(Int32, Int32))
        x = area.inner(1).x + INDENT
        visible(completions).map do |completion|
          width = CryTUI::TextWidth.width(label(completion))
          span = {x, x + width - 1}
          x += width + GAP
          span
        end
      end
    end

    # The which-key menu that opens while a key sequence is half typed. It
    # floats above the palette, is as tall as the pending sequence needs, and
    # never grows past the space it has.
    module WhichKeyLayout
      extend self

      MIN_WIDTH = 22

      def compute(area : CryTUI::Rect, entries : Array(Keymap::Entry), anchor : CryTUI::Rect) : CryTUI::Rect
        return CryTUI::Rect.new(area.x, area.y, 0, 0) if entries.empty? || area.width < MIN_WIDTH

        width = entries.max_of? { |entry| CryTUI::TextWidth.width(entry_text(entry)) } || 0
        width = { {width + 2, MIN_WIDTH}.max, area.width - 4 }.min
        available = {anchor.y - area.y, 3}.max
        height = {entries.size + 2, available}.min
        CryTUI::Rect.new(area.x + 2, {anchor.y - height, area.y}.max, width, height)
      end

      # The entries that fit inside the panel once its borders are taken.
      def visible(entries : Array(Keymap::Entry), rect : CryTUI::Rect) : Array(Keymap::Entry)
        entries.first({rect.height - 2, 0}.max)
      end

      # One menu row. The widget splits this into styled spans that concatenate
      # back to exactly this string, so the measured width stays honest.
      def entry_text(entry : Keymap::Entry) : String
        " #{entry.token}  #{entry.group ? "+" : ""}#{entry.label} "
      end
    end
  end
end
