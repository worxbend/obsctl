require "./list_cursor"

module Obsctl
  module TUI
    # What the scene-profile editor is holding while it is open.
    #
    # The draft is deliberately separate from `DashboardState#scene_profiles`:
    # toggling a scene has to repaint immediately, but must not change what the
    # dashboard shows until the user saves, and Esc has to be able to throw the
    # whole draft away. `name` is empty for a draft nobody has named yet, which
    # is what turns Enter into a prompt instead of a save.
    class SceneProfileEditorState
      include ListCursor

      property active : Bool
      property cursor : Int32
      property name : String
      property hidden : Set(String)
      # True while the user is typing a name. The modal's keys mean different
      # things in the two sub-modes -- `t` toggles a scene in one and types a
      # letter in the other -- so the mode has to be part of the state rather
      # than inferred.
      property naming : Bool
      property name_input : String
      # The saved profile this draft was loaded from, or nil for a draft that is
      # not based on one.
      #
      # This is what makes renaming possible: saving under a different name
      # renames that profile in place instead of leaving the original behind
      # beside a copy of it.
      property origin_name : String?

      def initialize(@active = false, @cursor = 0, @name = "", @hidden = Set(String).new, @naming = false, @name_input = "", @origin_name = nil)
      end
    end
  end
end
