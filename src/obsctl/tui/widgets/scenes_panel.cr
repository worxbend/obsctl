require "../model"

module Obsctl::TUI::Widgets
  # Renders the flat scene list and configured scene metadata.
  class ScenesPanel
    # Writes the scenes panel to `io`.
    def render(model : Model, io : IO) : Nil
      io.puts "Scenes"
      scenes = model.snapshot.try(&.scenes) || [] of ::Obsctl::OBS::State::SceneState
      if scenes.empty?
        io.puts "  -"
        return
      end

      scenes.each do |scene|
        marker = scene.active ? ">" : " "
        io.puts "#{marker} #{scene.name}#{metadata(scene)}"
      end
    end

    private def metadata(scene : ::Obsctl::OBS::State::SceneState) : String
      parts = [] of String
      parts << "alias=#{scene.alias}" if scene.alias
      parts << "key=#{scene.shortcut}" if scene.shortcut
      parts << "group=#{scene.group}" if scene.group
      return "" if parts.empty?

      " [" + parts.join(" ") + "]"
    end
  end
end
