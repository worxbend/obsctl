module Obsctl
  module TUI
    module Input
      # Mutable state for the command palette edit line.
      class CommandMode
        getter line = ""
        getter? active = false

        # Opens the command palette with the configured command prefix.
        def open(prefix : String = "/") : Nil
          @active = true
          @line = prefix
        end

        # Appends one printable character while active.
        def append(char : Char) : Nil
          return unless @active

          @line += char
        end

        # Removes the previous character while active.
        def backspace : Nil
          return unless @active
          return if @line.empty?

          @line = @line[0...-1]
        end

        # Clears the line and closes command mode.
        def clear : Nil
          @line = ""
          @active = false
        end

        # Closes command mode and returns the submitted non-empty command.
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
