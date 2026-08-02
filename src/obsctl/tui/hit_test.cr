require "../../crytui"
require "./layout"
require "./model"

module Obsctl
  module TUI
    # Where a pointer landed on the dashboard.
    #
    # `index` is the item under the pointer, or nil for a click that hit a
    # panel but not one of its rows -- a border, a title, or empty space below
    # the last item. That still identifies a panel, which is enough to move
    # focus.
    record PointerTarget,
      panel : FocusPanel,
      index : Int32? = nil,
      on_mute_control : Bool = false

    # Resolves screen coordinates to the panel and row underneath them.
    #
    # The dashboard is drawn from a pure layout function and lists whose scroll
    # offset is derived, not stored, so the same inputs that produced a frame
    # can be replayed to ask what is at a point. Nothing about the last render
    # has to be cached.
    module HitTest
      extend self

      # Columns the mute glyph and its trailing space occupy at the start of an
      # audio row, matching the leading span in `Widgets::Audio`.
      MUTE_CONTROL_WIDTH = 3

      def resolve(model : Model, area : CryTUI::Rect, column : Int32, row : Int32) : PointerTarget?
        return unless model.view.main?
        return if model.command_palette.active

        areas = DashboardLayout.compute(area, model.streaming?)
        if target = list_target(FocusPanel::Scenes, areas.scenes, model, column, row)
          return target
        end
        if target = audio_target(areas.audio, model, column, row)
          return target
        end
        if target = list_target(FocusPanel::Profiles, areas.profiles, model, column, row)
          return target
        end
        list_target(FocusPanel::Collections, areas.collections, model, column, row)
      end

      # The theme row under the pointer in the appearance lab.
      def settings_index(model : Model, area : CryTUI::Rect, column : Int32, row : Int32) : Int32?
        return unless model.view.settings?

        themes = SettingsLayout.compute(area).themes
        return unless contains?(themes, column, row)

        item_at(themes, Array.new(Theme::ALL.size, 1), model.settings_cursor, row)
      end

      # The panel the command palette is drawn in, so a click outside it can be
      # told from a click on it.
      def palette_area(model : Model, area : CryTUI::Rect) : CryTUI::Rect
        DashboardLayout.compute(area, model.streaming?).palette
      end

      # The completion chip under the pointer, or nil anywhere else.
      def palette_completion(model : Model, area : CryTUI::Rect, column : Int32, row : Int32) : Int32?
        palette = palette_area(model, area)
        return unless row == PaletteLayout.completion_row(palette)

        PaletteLayout
          .chips(model.command_palette.completions, palette)
          .index { |span| column >= span[0] && column <= span[1] }
      end

      # Where the which-key menu is drawn for the sequence being typed.
      def which_key_area(model : Model, area : CryTUI::Rect) : CryTUI::Rect
        WhichKeyLayout.compute(area, Keymap.continuations(model.pending_sequence), palette_area(model, area))
      end

      # The which-key row under the pointer, so the menu can be clicked as well
      # as typed.
      def which_key_entry(model : Model, area : CryTUI::Rect, column : Int32, row : Int32) : Keymap::Entry?
        entries = Keymap.continuations(model.pending_sequence)
        rect = WhichKeyLayout.compute(area, entries, palette_area(model, area))
        return unless contains?(rect, column, row)

        WhichKeyLayout.visible(entries, rect)[row - inner_area(rect).y]?
      end

      private def list_target(panel : FocusPanel, area : CryTUI::Rect, model : Model, column : Int32, row : Int32) : PointerTarget?
        return unless contains?(area, column, row)
        count = case panel
                when .scenes?      then model.scenes.size
                when .profiles?    then model.profiles.size
                when .collections? then model.scene_collections.size
                else                    0
                end
        index = item_at(area, Array.new(count, 1), cursor_for(model, panel), row)
        PointerTarget.new(panel, index)
      end

      private def audio_target(area : CryTUI::Rect, model : Model, column : Int32, row : Int32) : PointerTarget?
        return unless contains?(area, column, row)
        inputs = model.audio_inputs
        # An input only grows a second row once a meter level has arrived for
        # it, so heights are per item rather than a fixed stride.
        heights = inputs.map { |input| model.meter_levels[input.name]? ? 2 : 1 }
        index = item_at(area, heights, model.audio_cursor, row)
        return PointerTarget.new(FocusPanel::Audio) unless index

        inner = inner_area(area)
        first_row = row_of(area, heights, model.audio_cursor, index)
        on_mute = row == first_row && column < inner.x + MUTE_CONTROL_WIDTH
        PointerTarget.new(FocusPanel::Audio, index, on_mute)
      end

      # The item occupying `row`, or nil when the pointer is on the chrome or
      # past the last item.
      private def item_at(area : CryTUI::Rect, heights : Array(Int32), cursor : Int32, row : Int32) : Int32?
        inner = inner_area(area)
        return if heights.empty? || inner.height <= 0
        return unless row >= inner.y && row < inner.bottom

        offset = CryTUI::Widgets::List.visible_offset(heights, cursor, inner.height)
        y = inner.y
        (offset...heights.size).each do |index|
          height = heights[index]
          return index if row < y + height
          y += height
          break if y >= inner.bottom
        end
        nil
      end

      # The first screen row of an item already known to be visible.
      private def row_of(area : CryTUI::Rect, heights : Array(Int32), cursor : Int32, index : Int32) : Int32
        inner = inner_area(area)
        offset = CryTUI::Widgets::List.visible_offset(heights, cursor, inner.height)
        inner.y + (offset...index).sum { |i| heights[i] }
      end

      # Panels are drawn inside a one-cell border on every side.
      private def inner_area(area : CryTUI::Rect) : CryTUI::Rect
        CryTUI::Rect.new(area.x + 1, area.y + 1, {area.width - 2, 0}.max, {area.height - 2, 0}.max)
      end

      private def cursor_for(model : Model, panel : FocusPanel) : Int32
        case panel
        when .scenes?      then model.scene_cursor
        when .audio?       then model.audio_cursor
        when .profiles?    then model.profile_cursor
        when .collections? then model.collection_cursor
        else                    0
        end
      end

      private def contains?(area : CryTUI::Rect, column : Int32, row : Int32) : Bool
        column >= area.x && column < area.right && row >= area.y && row < area.bottom
      end
    end
  end
end
