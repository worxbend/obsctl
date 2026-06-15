require "../model"

module Obsctl::TUI::Widgets
  class CommandPalette
    def render(model : Model, io : IO) : Nil
      io.puts model.last_result || "Type /help for commands."
      io.print "> #{model.command_line}"
    end
  end
end
