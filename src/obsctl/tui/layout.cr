require "../../crytui"
require "./keymap"
require "./model"
require "./scene_picker"

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
      #
      # Exhaustive `in` rather than `when`/`else`: a fifth panel then becomes a
      # compile error here instead of silently drawing in the collections
      # rectangle.
      def panel(focus : FocusPanel) : CryTUI::Rect
        case focus
        in .scenes?      then scenes
        in .audio?       then audio
        in .profiles?    then profiles
        in .collections? then collections
        end
      end
    end

    # Geometry every bordered panel shares, so the widgets and the hit test
    # agree on which cells a panel's content occupies.
    module PanelGeometry
      extend self

      # Panels are drawn inside a one-cell border on every side.
      #
      # Not `CryTUI::Rect#inner(1)`: that clamps the margin to half the extent,
      # so on a rect one or two cells wide it keeps content the border would
      # have covered here. Clicks have to land on the row that was drawn, so
      # the subtraction stays literal.
      def inner(area : CryTUI::Rect) : CryTUI::Rect
        CryTUI::Rect.new(area.x + 1, area.y + 1, {area.width - 2, 0}.max, {area.height - 2, 0}.max)
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

      def inner(area : CryTUI::Rect) : CryTUI::Rect
        PanelGeometry.inner(area)
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

    # The scene picker overlay: a centred box listing every scene beside the
    # key that switches to it.
    #
    # Centred rather than anchored to the scenes panel because it is a modal --
    # while it is open nothing else takes keys, so putting it in the middle of
    # the screen says so. Shared with the hit test, the same way every other
    # overlay's geometry is, so a click resolves against the row that was
    # actually painted.
    module ScenePickerLayout
      extend self

      MIN_WIDTH = 24
      # Long scene names are truncated by the list rather than allowed to push
      # the box out to the full width of a wide terminal.
      MAX_WIDTH = 64
      # A border row above and below, so the box is this much taller than the
      # rows it can show.
      CHROME_HEIGHT = 2
      # Below this the box would show one scene at most, which is worse than
      # leaving the dashboard alone and saying nothing.
      MIN_HEIGHT = 5

      # Takes the model rather than a scene list so the title it measures is
      # built by the same code the widget draws, which is what stops the box
      # from being sized to something other than what it renders.
      def compute(area : CryTUI::Rect, model : Model) : CryTUI::Rect
        entries = model.scene_picker_entries
        empty = CryTUI::Rect.new(area.x, area.y, 0, 0)
        return empty if entries.empty?
        return empty if area.width < MIN_WIDTH + 4 || area.height < MIN_HEIGHT + 2

        widest = entries.max_of { |entry| CryTUI::TextWidth.width(row_text(entry)) }
        # Widened to the title as well as to the rows: a picker whose scene
        # names are all short would otherwise be too narrow to print its own
        # "esc close" hint, which is the only way out of a modal.
        # Both get `+ 2` for the border cell either side, which is the space
        # the block takes before any of its content is drawn.
        title = CryTUI::TextWidth.width(title_parts(model, entries.size).join)
        wanted = {widest + 2, title + 2, MIN_WIDTH}.max
        width = {wanted, MAX_WIDTH, area.width - 4}.min
        height = {entries.size + CHROME_HEIGHT, area.height - 2}.min
        CryTUI::Rect.new(
          area.x + (area.width - width) // 2,
          area.y + (area.height - height) // 2,
          width,
          height
        )
      end

      # The title in the three pieces the widget styles separately: heading,
      # scene count, key hint. They concatenate to exactly what `compute`
      # measured.
      def title_parts(model : Model, count : Int32) : Tuple(String, String, String)
        {
          " #{model.symbol("🎬", "S")}  Switch scene ",
          " #{count.to_s.rjust(2, '0')} ",
          "  #{model.symbol("↵ switch · esc close", "Enter switch  Esc close")} ",
        }
      end

      # One picker row. The widget splits this into styled spans that
      # concatenate back to exactly this string, so the width measured here is
      # the width that gets drawn.
      #
      # Unlabelled scenes keep the same indent as labelled ones so the names
      # stay in one column.
      def row_text(entry : ScenePicker::Entry) : String
        " #{entry.label || ' '}  #{entry.scene.name} "
      end
    end

    # The scene-preset editor overlay: every scene the daemon reported, hidden
    # ones included, because this is the one surface that can bring a hidden
    # scene back.
    #
    # Centred and shared with the hit test for the same reasons
    # `ScenePickerLayout` is: it is a modal, so the middle of the screen says
    # so, and a click has to resolve against the row that was actually painted.
    module ScenePresetsLayout
      extend self

      # Wider than the picker's floor because the rows carry a hide marker as
      # well as a scene name.
      MIN_WIDTH = 28
      # Long scene names are truncated by the list rather than allowed to push
      # the box out to the full width of a wide terminal. Wider than the
      # picker's floor because the hint row spells out five keys rather than
      # one.
      MAX_WIDTH = 72
      # A border row above and below, plus the row the hints keep for
      # themselves, so the box is this much taller than the rows it can show.
      CHROME_HEIGHT = 3
      # Below this the box would show two scenes at most, which is worse than
      # leaving the dashboard alone and saying nothing.
      MIN_HEIGHT = 6

      # Takes the model rather than a scene list so the title it measures is
      # built by the same code the widget draws, which is what stops the box
      # from being sized to something other than what it renders.
      def compute(area : CryTUI::Rect, model : Model) : CryTUI::Rect
        scenes = model.all_scenes
        empty = CryTUI::Rect.new(area.x, area.y, 0, 0)
        return empty if scenes.empty?
        return empty if area.width < MIN_WIDTH + 4 || area.height < MIN_HEIGHT + 2

        widest = scenes.max_of { |scene| CryTUI::TextWidth.width(row_text(model, scene)) }
        # Widened to the title and to the hint row as well as to the rows, so a
        # preset whose scene names are all short still has room for the keys
        # that are the only way out of a modal. Each gets `+ 2` for the border
        # cell either side.
        #
        # The title is measured at the widest the box may end up, because that
        # is the most room the name it carries can be given; a narrower box
        # fits the name to what it actually has (see `title_parts`).
        title = CryTUI::TextWidth.width(title_parts(model).join)
        hints = CryTUI::TextWidth.width(hint_text(model))
        wanted = {widest + 2, title + 2, hints + 2, MIN_WIDTH}.max
        width = {wanted, MAX_WIDTH, area.width - 4}.min
        height = {scenes.size + CHROME_HEIGHT, area.height - 2}.min
        CryTUI::Rect.new(
          area.x + (area.width - width) // 2,
          area.y + (area.height - height) // 2,
          width,
          height
        )
      end

      # The box the scene list gets: every inner row except the last, which
      # belongs to the hints.
      #
      # Returned as a box with a border rather than as the inner rows, because
      # both the widget and the hit test take the inside of it and they have to
      # agree on where that is down to the row.
      def list_area(rect : CryTUI::Rect) : CryTUI::Rect
        CryTUI::Rect.new(rect.x, rect.y, rect.width, {rect.height - 1, 0}.max)
      end

      # The screen row the hints are drawn on: the last one inside the border.
      def hint_row(rect : CryTUI::Rect) : Int32
        rect.bottom - 2
      end

      # Every key the editor answers to, on a row of its own under the list.
      #
      # They are not in the title because the title carries the preset's name,
      # which is text the reader typed and can be any length. Sharing one line
      # with it meant the block silently cut the end off, and the end is where
      # "esc close" -- the only way out of the modal -- was. A row of its own is
      # also what makes room to mention the keys that cycle between saved
      # presets, which is the whole point of having more than one.
      #
      # `width` is the box the row has to fit in. A terminal too narrow for the
      # full row gets a shorter one that still names a key and what it does,
      # rather than the full row with its tail cut off.
      def hint_text(model : Model, width : Int32 = MAX_WIDTH) : String
        return model.symbol(" ↵ confirm · esc cancel ", " Enter confirm  Esc cancel ") if model.scene_preset_editor.naming

        full = model.symbol(
          " t hide · n name · ⇥ switch preset · ↵ save · esc close ",
          " t hide  n name  Tab switch preset  Enter save  Esc close "
        )
        return full if CryTUI::TextWidth.width(full) <= width - 2

        model.symbol(" t hide · ↵ save · esc close ", " t hide  Enter save  Esc close ")
      end

      # The title in the two pieces the widget styles separately: the heading
      # and the draft's name. They concatenate to exactly what `compute`
      # measured.
      #
      # `width` is the box the title has to fit in. The name is fitted to
      # whatever the heading leaves of it rather than allowed to run past the
      # border, because a block clips its title without saying so and the name
      # is unbounded: nothing stops a reader typing sixty characters.
      #
      # While a name is being typed the name piece becomes the input line, so
      # the box is always measured around what is actually drawn on it rather
      # than around the wider of two states.
      def title_parts(model : Model, width : Int32 = MAX_WIDTH) : Tuple(String, String)
        text = heading(model)
        {text, name_part(model, width - 2 - CryTUI::TextWidth.width(text))}
      end

      # One editor row. The widget splits this into styled spans that
      # concatenate back to exactly this string, so the width measured here is
      # the width that gets drawn.
      def row_text(model : Model, scene : OBS::State::SceneState) : String
        " #{marker(model, model.scene_preset_editor.hidden.includes?(scene.name))}  #{scene.name} "
      end

      # The hide state is carried by a marker as well as by the widget's
      # dimming, because a terminal that ignores the dim attribute would
      # otherwise draw hidden and visible scenes identically.
      #
      # Both markers are one cell wide, so toggling a scene never changes the
      # width the box was measured against.
      def marker(model : Model, hidden : Bool) : String
        hidden ? model.symbol("○", "-") : model.symbol("●", "+")
      end

      private def heading(model : Model) : String
        " #{model.symbol("🗂", "P")}  Scene presets "
      end

      # The name badge, or the line being typed while one is being entered,
      # fitted into the `room` cells the heading left over. A box too narrow to
      # show a name at all drops the badge rather than the border.
      private def name_part(model : Model, room : Int32) : String
        return "" if room <= 2

        editor = model.scene_preset_editor
        return naming_part(model, editor, room) if editor.naming

        " #{CryTUI::TextWidth.truncate(editor.name.empty? ? "unnamed" : editor.name, room - 2, ellipsis(model))} "
      end

      # The typed name is followed by a block so the caret is visible where the
      # terminal's own cursor is not: the dashboard parks that in the corner.
      #
      # What scrolls out of a full field is the beginning, not the end: the
      # caret has to stay on screen or the reader is typing blind, with nothing
      # on the display changing as they do.
      private def naming_part(model : Model, editor : ScenePresetEditorState, room : Int32) : String
        prompt = " #{model.symbol("❯", ">")} "
        typed = "#{editor.name_input}#{model.advanced_ui ? "█" : "_"}"
        field = CryTUI::TextWidth.truncate_start(typed, room - CryTUI::TextWidth.width(prompt) - 1, ellipsis(model))
        "#{prompt}#{field} "
      end

      private def ellipsis(model : Model) : String
        model.symbol("…", "~")
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
      #
      # When they do not all fit, one further row is given up so the widget can
      # say how many were left out. A menu that stops without saying so turns
      # every binding past the cut into one nobody knows is there -- and where
      # the menu is cut is decided by the height of the terminal, so the reader
      # has no way to tell a short list from a truncated one.
      def visible(entries : Array(Keymap::Entry), rect : CryTUI::Rect) : Array(Keymap::Entry)
        capacity = {rect.height - 2, 0}.max
        return entries if entries.size <= capacity

        entries.first({capacity - 1, 0}.max)
      end

      # How many entries the panel had no room for, which is what the last row
      # reports when it is not showing one.
      def overflow(entries : Array(Keymap::Entry), rect : CryTUI::Rect) : Int32
        entries.size - visible(entries, rect).size
      end

      # The row that stands in for the entries that did not fit.
      def overflow_text(count : Int32) : String
        " +#{count} more "
      end

      # One menu row. The widget splits this into styled spans that concatenate
      # back to exactly this string, so the measured width stays honest.
      def entry_text(entry : Keymap::Entry) : String
        " #{entry.token}  #{entry.group ? "+" : ""}#{entry.label} "
      end
    end
  end
end
