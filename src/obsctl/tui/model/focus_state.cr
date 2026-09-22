require "./focus_panel"
require "./list_cursor"

module Obsctl
  module TUI
    # Which panel is pointed at, and where the cursor sits in each.
    #
    # One cursor per panel, keyed by the panel it belongs to.
    #
    # These were four separate fields, which made every operation over "the
    # cursor of whichever panel is focused" a four-armed `case` on
    # `FocusPanel` — one to read it, one to move it, one to clamp them all,
    # and one more in the dispatcher to place it after a click. Adding a
    # fifth panel meant finding every one of them, and missing one failed
    # quietly, as a cursor that simply stopped responding in that panel.
    # Keyed by the enum, each of those becomes a lookup.
    class FocusState
      property focus : FocusPanel
      @cursors : Hash(FocusPanel, Int32)

      def initialize(@focus = FocusPanel::Scenes)
        @cursors = FocusPanel.values.to_h { |panel| {panel, 0} }
      end

      def cursor(panel : FocusPanel = @focus) : Int32
        @cursors[panel]
      end

      # Places a panel's cursor without moving focus, which is what a click
      # needs: the pointer says both which panel and which row.
      def set_cursor(panel : FocusPanel, index : Int32) : Nil
        @cursors[panel] = index
      end

      # Cursor moves are clamped rather than wrapped: `G` on the last item and
      # a half page past the end both stop at the end, the way they do in vim.
      # The row count arrives as an argument because the lists live on
      # `DashboardState`, not here.
      def move_to(panel : FocusPanel, index : Int32, count : Int32) : Nil
        @cursors[panel] = index.clamp(0, {count - 1, 0}.max)
      end

      # Pulls one panel's cursor back inside its list after the list changes,
      # so a scene deleted in OBS cannot leave a cursor pointing past the end.
      def clamp(panel : FocusPanel, count : Int32) : Nil
        @cursors[panel] = ListCursor.clamped(@cursors[panel], count)
      end

      # The per-panel names the widgets and the hit test read.
      {% for panel, name in {Scenes: "scene", Audio: "audio", Profiles: "profile", Collections: "collection"} %}
        def {{ name.id }}_cursor : Int32
          cursor(FocusPanel::{{ panel.id }})
        end

        def {{ name.id }}_cursor=(index : Int32) : Nil
          set_cursor(FocusPanel::{{ panel.id }}, index)
        end
      {% end %}
    end
  end
end
