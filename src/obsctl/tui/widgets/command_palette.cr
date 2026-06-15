require "../model"

module Obsctl::TUI::Widgets
  # Renders the command palette prompt and last command result.
  class CommandPalette
    # Writes the command palette panel to `io`.
    def render(model : Model, io : IO) : Nil
      io.puts model.last_result || "Type /help for commands."
      io.print "> #{model.command_line}"
    end
  end
end
