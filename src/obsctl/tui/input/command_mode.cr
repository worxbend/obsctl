module Obsctl
  module TUI
    module Input
      class CommandMode
        getter line = ""

        def append(char : Char) : Nil
          @line += char
        end

        def clear : Nil
          @line = ""
        end
      end
    end
  end
end
