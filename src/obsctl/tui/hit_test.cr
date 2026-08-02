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
