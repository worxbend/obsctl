module Obsctl
  module TUI
    module Input
      class CommandMode
        getter line = ""
        getter? active = false

        def open(prefix : String = "/") : Nil
          @active = true
          @line = prefix
        end

        def append(char : Char) : Nil
          return unless @active

          @line += char
        end

        def backspace : Nil
          return unless @active
          return if @line.empty?

          @line = @line[0...-1]
        end

        def clear : Nil
          @line = ""
          @active = false
        end

        def submit : String?
          return nil unless @active

          submitted = @line.strip
          clear
          submitted.empty? ? nil : submitted
        end
      end
    end
  end
end
