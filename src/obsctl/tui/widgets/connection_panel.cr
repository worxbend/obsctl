require "../model"

module Obsctl::TUI::Widgets
  class ConnectionPanel
    def render(model : Model, io : IO) : Nil
      snapshot = model.snapshot
      io.puts "Connection"
      io.puts "  OBS: #{snapshot.try(&.connected) ? "connected" : "disconnected"}"
      io.puts "  Updated: #{snapshot.try(&.updated_at.to_rfc3339) || "-"}"

      if error = snapshot.try(&.last_error)
        io.puts "  Error: #{error}"
      end
    end
  end
end
