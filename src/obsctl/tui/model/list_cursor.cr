module Obsctl
  module TUI
    # Moving a cursor through a list, and pulling it back inside one.
    #
    # The three modal cursors -- the scene picker, the scene-profile list and
    # the scene-profile editor -- each wrote the move out longhand,
    # `{cursor - 1, 0}.max` one way and `{cursor + 1, {count - 1, 0}.max}.min`
    # the other, and `Model#clamp_cursors` wrote the clamp out four times over.
    # Named once here, each site says which list it is moving through instead
    # of restating what moving through a list means.
    #
    # `moved` is deliberately asymmetric: going up stops at zero without
    # consulting `count`, while going down stops at the last row. A cursor
    # sitting past the end -- which is what a list that has just shrunk leaves
    # behind, until the next `clamp_cursors` -- therefore keeps its place when
    # the user moves up, exactly as it did before. Folding the two directions
    # into one `clamp` would read more tidily and would quietly change that.
    #
    # The dashboard panels' own rule is a different one and lives on
    # `FocusState#move_to`: it clamps both directions, because `G` and a
    # half-page jump have to land on the last row rather than past it.
    module ListCursor
      def self.moved(cursor : Int32, delta : Int32, count : Int32) : Int32
        return {cursor + delta, 0}.max if delta < 0

        {cursor + delta, {count - 1, 0}.max}.min
      end

      # `count - 1` floored at zero, so an empty list parks the cursor on row
      # zero instead of on -1.
      def self.clamped(cursor : Int32, count : Int32) : Int32
        cursor.clamp(0, {count - 1, 0}.max)
      end

      # Mixed into the three modal states, which each hold their cursor as
      # `@cursor`.
      def move(delta : Int32, count : Int32) : Nil
        @cursor = ListCursor.moved(@cursor, delta, count)
      end

      def clamp(count : Int32) : Nil
        @cursor = ListCursor.clamped(@cursor, count)
      end
    end
  end
end
