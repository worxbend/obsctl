require "./scene_profiles"

module Obsctl
  module TUI
    # The rows of the scene-profile list: "show every scene" first, then every
    # saved profile.
    #
    # "Show every scene" is a row rather than a gesture because turning
    # filtering off has to be as findable as turning it on -- a user who cannot
    # see how to get their scenes back is stuck with a dashboard that looks
    # broken.
    #
    # Labels are digits and nothing else, unlike the scene picker's `1`-`9`
    # then `a`-`z`: this modal spends its letters on verbs (`e` edit, `r`
    # rename, `n` new, `d` delete, `q` close), and a label that was also a verb
    # would make one of the two unreachable. Row number and label are the same
    # character, so `3` is always the third row.
    module SceneProfileList
      # One row: which saved profile it stands for (nil for the "show every
      # scene" row), what to print, and the key that activates it.
      record Entry,
        index : Int32,
        name : String,
        profile : SceneProfile?,
        active : Bool,
        label : Char?

      SHOW_EVERY_SCENE = "Show every scene"

      extend self

      def entries(profiles : SceneProfiles) : Array(Entry)
        rows = [Entry.new(0, SHOW_EVERY_SCENE, nil, profiles.active.nil?, '0')]
        profiles.profiles.each_with_index do |profile, position|
          index = position + 1
          rows << Entry.new(index, profile.name, profile, profiles.active == profile.name, index <= 9 ? ('0' + index) : nil)
        end
        rows
      end

      # The row a key press selects, or nil when nothing carries that digit.
      def index_for(entries : Array(Entry), character : Char) : Int32?
        entries.find { |entry| entry.label == character }.try(&.index)
      end
    end
  end
end
