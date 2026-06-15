require "../model"

module Obsctl::TUI::Widgets
  # Renders recent server log messages delivered over IPC.
  class LogPanel
    # Writes the recent-log panel to `io`.
    def render(model : Model, io : IO) : Nil
      io.puts "Recent Logs"
      logs = model.logs.last(5)
      if logs.empty?
        io.puts "  -"
        return
      end

      logs.each do |entry|
        io.puts "  #{entry}"
      end
    end
  end
end
