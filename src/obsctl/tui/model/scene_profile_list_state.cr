require "./list_cursor"

module Obsctl
  module TUI
    # What the scene-profile list is holding while it is open.
    #
    # A class of its own rather than loose properties on the model, because
    # this modal has a sub-mode: `confirming` is a delete waiting for its
    # second press, during which the keys mean different things -- the same
    # reason `SceneProfileEditorState` carries `naming` rather than inferring
    # it.
    class SceneProfileListState
      include ListCursor

      property active : Bool
      property cursor : Int32
      # True after the first `d`, while a delete waits for the second press.
      property confirming : Bool

      def initialize(@active = false, @cursor = 0, @confirming = false)
      end
    end
  end
end
