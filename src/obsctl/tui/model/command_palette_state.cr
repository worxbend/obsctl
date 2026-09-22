module Obsctl
  module TUI
    class CommandPaletteState
      property active : Bool
      property input : String
      property completions : Array(String)
      property completion_index : Int32?

      def initialize(@active = false, @input = "", @completions = [] of String, @completion_index = nil)
      end

      def cycle_next
        return if @completions.empty?
        index = @completion_index
        next_index = index ? (index + 1) % @completions.size : 0
        @completion_index = next_index
        @input = @completions[next_index]
      end

      def cycle_previous
        return if @completions.empty?
        next_index = case index = @completion_index
                     when Nil then @completions.size - 1
                     when 0   then @completions.size - 1
                     else          index - 1
                     end
        @completion_index = next_index
        @input = @completions[next_index]
      end
    end
  end
end
