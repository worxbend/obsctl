require "../model"

module Obsctl::TUI::Widgets
  class Header
    def render(model : Model, io : IO) : Nil
      snapshot = model.snapshot
      status = snapshot.try(&.connected) ? "connected" : "disconnected"
      current_scene = snapshot.try(&.current_scene) || "-"

      io.puts "obsctl-cr | OBS #{status} | scene #{current_scene}"
      io.puts "OBS #{snapshot.try(&.obs_studio_version) || "-"} | obs-websocket #{snapshot.try(&.obs_websocket_version) || "-"}"
    end
  end
end
