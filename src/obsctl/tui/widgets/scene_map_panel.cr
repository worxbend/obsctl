require "../model"

module Obsctl::TUI::Widgets
  # Renders grouped scene names with the active scene marker.
  class SceneMapPanel
    # Writes the scene map panel to `io`.
    def render(model : Model, io : IO) : Nil
      io.puts "Scene Map"
      scenes = model.snapshot.try(&.scenes) || [] of ::Obsctl::OBS::State::SceneState
      if scenes.empty?
        io.puts "  -"
        return
      end

      grouped(scenes).each do |group, items|
        io.puts "  #{group}"
        items.each do |scene|
          marker = scene.active ? "*" : "-"
          io.puts "    #{marker} #{scene.name}"
        end
      end
    end

    private def grouped(scenes : Array(::Obsctl::OBS::State::SceneState)) : Hash(String, Array(::Obsctl::OBS::State::SceneState))
      groups = Hash(String, Array(::Obsctl::OBS::State::SceneState)).new { |hash, key| hash[key] = [] of ::Obsctl::OBS::State::SceneState }
      scenes.each do |scene|
        groups[scene.group || "Ungrouped"] << scene
      end
      groups
    end
  end
end
