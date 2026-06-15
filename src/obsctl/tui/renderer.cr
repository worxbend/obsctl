require "./model"
require "./widgets/audio_panel"
require "./widgets/command_palette"
require "./widgets/connection_panel"
require "./widgets/header"
require "./widgets/log_panel"
require "./widgets/scene_map_panel"
require "./widgets/scenes_panel"

module Obsctl
  module TUI
    class Renderer
      def initialize
        @header = Widgets::Header.new
        @connection_panel = Widgets::ConnectionPanel.new
        @scenes_panel = Widgets::ScenesPanel.new
        @scene_map_panel = Widgets::SceneMapPanel.new
        @audio_panel = Widgets::AudioPanel.new
        @log_panel = Widgets::LogPanel.new
        @command_palette = Widgets::CommandPalette.new
      end

      def render(model : Model, io : IO = STDOUT) : Nil
        io.print "\e[2J\e[H"
        @header.render(model, io)
        separator(io)
        @connection_panel.render(model, io)
        separator(io)
        @scenes_panel.render(model, io)
        io.puts
        @scene_map_panel.render(model, io)
        io.puts
        @audio_panel.render(model, io)
        separator(io)
        @log_panel.render(model, io)
        separator(io)
        @command_palette.render(model, io)
      end

      private def separator(io : IO) : Nil
        io.puts "-" * 72
      end
    end
  end
end
