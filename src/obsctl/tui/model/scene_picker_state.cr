require "./list_cursor"

module Obsctl
  module TUI
    # What the scene picker overlay is holding while it is open.
    #
    # The picker has no sub-mode to carry, which is why it stayed two plain
    # properties on the model while the list and the editor got state objects:
    # nothing about it needed behavior of its own. It joined them when the
    # model became a composition, because three modal overlays that each
    # answer `active` and hold a `ListCursor` cursor are one pattern, not
    # three -- the dispatcher drives them the same way, and
    # `Model#clamp_cursors` pulls all three back inside their lists in one
    # breath instead of reaching for a loose property for one of them.
    class ScenePickerState
      include ListCursor

      property active : Bool
      # The picker keeps its own cursor rather than borrowing the dashboard's
      # scene cursor, so opening it does not move the dashboard's selection
      # out from under whichever panel is focused, and closing it without
      # picking leaves the dashboard exactly as it was.
      property cursor : Int32

      def initialize(@active = false, @cursor = 0)
      end
    end
  end
end
