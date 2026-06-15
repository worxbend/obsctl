module Obsctl
  module TUI
    record Rect, x : Int32, y : Int32, width : Int32, height : Int32

    module Layout
      def self.default(width : Int32, height : Int32)
        {
          header: Rect.new(0, 0, width, 3),
          left:   Rect.new(0, 3, width // 4, height - 8),
          center: Rect.new(width // 4, 3, width // 2, height - 8),
          right:  Rect.new((width * 3) // 4, 3, width // 4, height - 8),
          bottom: Rect.new(0, height - 5, width, 5),
        }
      end
    end
  end
end
