module Obsctl
  module TUI
    enum FocusPanel
      Scenes
      Audio
      Profiles
      Collections

      def left : self
        audio? ? Scenes : (collections? ? Profiles : self)
      end

      def right : self
        scenes? ? Audio : (profiles? ? Collections : self)
      end

      def up : self
        profiles? ? Scenes : (collections? ? Audio : self)
      end

      def down : self
        scenes? ? Profiles : (audio? ? Collections : self)
      end
    end
  end
end
