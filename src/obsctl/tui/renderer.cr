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
      DEFAULT_WIDTH  = 72
      DEFAULT_HEIGHT = 24
      MIN_WIDTH      = 40
      MIN_HEIGHT     = 12

      def initialize
        @header = Widgets::Header.new
        @connection_panel = Widgets::ConnectionPanel.new
        @scenes_panel = Widgets::ScenesPanel.new
        @scene_map_panel = Widgets::SceneMapPanel.new
        @audio_panel = Widgets::AudioPanel.new
        @log_panel = Widgets::LogPanel.new
        @command_palette = Widgets::CommandPalette.new
        @previous_frame = [] of String
      end

      def render(model : Model, io : IO = STDOUT, width : Int32 = DEFAULT_WIDTH, height : Int32 = DEFAULT_HEIGHT) : Nil
        viewport = Viewport.new(width, height)
        frame = build_frame(model, viewport)

        io.print "\e[2J\e[H"
        frame.each { |line| io.puts line }
        @previous_frame = frame
      end

      def render_incremental(model : Model, io : IO = STDOUT, width : Int32 = DEFAULT_WIDTH, height : Int32 = DEFAULT_HEIGHT) : Nil
        viewport = Viewport.new(width, height)
        frame = build_frame(model, viewport)
        if @previous_frame.empty?
          io.print "\e[2J\e[H"
          frame.each { |line| io.puts line }
        else
          write_diff(io, @previous_frame, frame, viewport)
        end
        @previous_frame = frame
      end

      def reset : Nil
        @previous_frame = [] of String
      end

      private def build_frame(model : Model, viewport : Viewport) : Array(String)
        writer = FrameWriter.new(viewport)

        writer.write_lines(capture(model, @header), max_lines: 2)
        writer.separator
        writer.write_lines(capture(model, @connection_panel), max_lines: 4)
        writer.separator

        dynamic_height = {viewport.height - 16, 3}.max
        panel_height = {dynamic_height // 3, 3}.max
        writer.write_lines(capture(model, @scenes_panel), max_lines: panel_height)
        writer.blank
        writer.write_lines(capture(model, @scene_map_panel), max_lines: panel_height)
        writer.blank
        writer.write_lines(capture(model, @audio_panel), max_lines: panel_height)

        writer.separator
        writer.write_lines(capture(model, @log_panel), max_lines: 5)
        writer.separator
        writer.write_lines(capture(model, @command_palette), max_lines: 2)
        writer.lines
      end

      private def capture(model : Model, widget) : Array(String)
        io = IO::Memory.new
        widget.render(model, io)
        io.to_s.lines(chomp: true)
      end

      private def write_diff(io : IO, previous : Array(String), current : Array(String), viewport : Viewport) : Nil
        max_lines = {previous.size, current.size}.max
        max_lines.times do |index|
          old_line = previous[index]?
          new_line = current[index]?
          next if old_line == new_line

          row = index + 1
          replacement = new_line || ""
          io.print "\e[#{row};1H"
          io.print replacement.ljust(viewport.width)
        end
      end

      private record Viewport, width : Int32, height : Int32 do
        def initialize(width : Int32, height : Int32)
          @width = {width, MIN_WIDTH}.max
          @height = {height, MIN_HEIGHT}.max
        end
      end

      private class FrameWriter
        getter lines : Array(String)

        def initialize(@viewport : Viewport)
          @lines = [] of String
        end

        def write_lines(lines : Array(String), max_lines : Int32) : Nil
          lines.first(max_lines).each do |line|
            write_line(line)
          end
        end

        def separator : Nil
          write_line("-" * @viewport.width)
        end

        def blank : Nil
          write_line("")
        end

        private def write_line(line : String) : Nil
          return if @lines.size >= @viewport.height

          @lines << truncate(line)
        end

        private def truncate(line : String) : String
          return line if line.size <= @viewport.width
          return "" if @viewport.width <= 0
          return "~" if @viewport.width == 1

          "#{line[0, @viewport.width - 1]}~"
        end
      end
    end
  end
end
