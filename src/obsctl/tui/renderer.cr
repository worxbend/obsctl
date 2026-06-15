require "./model"

module Obsctl
  module TUI
    class Renderer
      def render(model : Model, io : IO = STDOUT) : Nil
        snapshot = model.snapshot
        io.print "\e[2J\e[H"
        status = snapshot.try(&.connected) ? "connected" : "disconnected"
        io.puts "obsctl-cr | #{status}"
        io.puts "OBS: #{snapshot.try(&.obs_studio_version) || "-"} | WebSocket: #{snapshot.try(&.obs_websocket_version) || "-"}"
        io.puts "-" * 72
        io.puts "Scenes"
        if snapshot
          snapshot.scenes.each do |scene|
            marker = scene.active ? ">" : " "
            alias_text = scene.alias ? " alias=#{scene.alias}" : ""
            shortcut_text = scene.shortcut ? " key=#{scene.shortcut}" : ""
            io.puts "#{marker} #{scene.name}#{alias_text}#{shortcut_text}"
          end
        end
        io.puts
        io.puts "Audio"
        if snapshot
          snapshot.audio_inputs.each do |input|
            muted = input.muted.nil? ? "?" : (input.muted ? "muted" : "live")
            volume = input.volume_percent ? "#{input.volume_percent}%" : "-"
            io.puts "  #{input.name} #{muted} vol=#{volume}"
          end
        end
        io.puts "-" * 72
        io.puts model.last_result || "Type /help for commands."
        io.print "> #{model.command_line}"
      end
    end
  end
end
