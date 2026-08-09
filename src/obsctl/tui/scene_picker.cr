require "../obs/state/scene_state"

module Obsctl
  module TUI
    # Label assignment for the scene picker.
    #
    # The picker exists so that switching scene costs two keystrokes --
    # `<leader>s` and then one label -- instead of moving a cursor down a list
    # and pressing Enter. That only works if every label is a single press, so
    # the alphabet is fixed and finite rather than, say, a typed search.
    #
    # Kept out of the widget because input resolution, rendering and hit
    # testing all need the same answer about which key belongs to which scene.
    module ScenePicker
      # `1`-`9` and then `a`-`z`: thirty-five scenes get a one-press label.
      #
      # Zero is left out so the digits line up with the row numbers the scenes
      # panel already prints, which start at 01. Scenes past the end of the
      # alphabet get no label and stay reachable with the arrow keys.
      LABELS = ('1'..'9').to_a + ('a'..'z').to_a

      # One row of the picker: the scene, where it sits in `Model#scenes`, and
      # the key that jumps to it.
      record Entry, index : Int32, scene : OBS::State::SceneState, label : Char?

      extend self

      # Labels every scene, letting a configured single-character `shortcut`
      # claim its key before the automatic sequence is handed out.
      #
      # A scene configured with `shortcut: b` already advertises `[b]` in the
      # scenes panel, so the picker has to honour it -- otherwise the two
      # surfaces would disagree about which key reaches that scene. Everything
      # else takes the next label nobody has claimed, in list order.
      #
      # Example: three scenes where the second is configured `shortcut: 1`.
      # The second scene claims `1`, so the first and third get `2` and `3`
      # rather than `1` and `2`.
      def entries(scenes : Array(OBS::State::SceneState)) : Array(Entry)
        claimed = {} of Int32 => Char
        taken = Set(Char).new
        scenes.each_with_index do |scene, index|
          label = reserved_label(scene)
          claimed[index] = label if label && taken.add?(label)
        end

        available = LABELS.reject { |label| taken.includes?(label) }
        position = 0
        scenes.map_with_index do |scene, index|
          label = claimed[index]?
          if label.nil? && (automatic = available[position]?)
            label = automatic
            position += 1
          end
          Entry.new(index, scene, label)
        end
      end

      # The scene a key press selects, or nil when nothing carries that label.
      #
      # Matching is case-insensitive so Shift held over a letter still lands,
      # which matters because the labels are typed in a hurry.
      def index_for(entries : Array(Entry), character : Char) : Int32?
        wanted = character.downcase
        entries.find { |entry| entry.label == wanted }.try(&.index)
      end

      # A configured shortcut usable as a picker label: exactly one character,
      # and one this picker can produce.
      #
      # Multi-character shortcuts such as `brb` are left alone -- they still
      # resolve on the command line and in the CLI, they just cannot be a
      # single keypress here.
      private def reserved_label(scene : OBS::State::SceneState) : Char?
        shortcut = scene.shortcut
        return unless shortcut && shortcut.size == 1

        character = shortcut[0].downcase
        LABELS.includes?(character) ? character : nil
      end
    end
  end
end
