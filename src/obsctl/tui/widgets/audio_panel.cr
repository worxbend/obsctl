require "../model"

module Obsctl::TUI::Widgets
  class AudioPanel
    def render(model : Model, io : IO) : Nil
      io.puts "Audio"
      inputs = model.snapshot.try(&.audio_inputs) || [] of ::Obsctl::OBS::State::AudioState
      if inputs.empty?
        io.puts "  -"
        return
      end

      inputs.each do |input|
        io.puts "  #{input.name} #{mute_text(input)} vol=#{volume_text(input)}#{metadata(input)}"
      end
    end

    private def mute_text(input : ::Obsctl::OBS::State::AudioState) : String
      input.muted.nil? ? "?" : (input.muted ? "muted" : "live")
    end

    private def volume_text(input : ::Obsctl::OBS::State::AudioState) : String
      percent = input.volume_percent
      percent ? "#{percent}%" : "-"
    end

    private def metadata(input : ::Obsctl::OBS::State::AudioState) : String
      parts = [] of String
      parts << "alias=#{input.alias}" if input.alias
      parts << "key=#{input.shortcut}" if input.shortcut
      return "" if parts.empty?

      " [" + parts.join(" ") + "]"
    end
  end
end
