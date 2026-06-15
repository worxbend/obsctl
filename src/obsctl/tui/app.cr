require "./model"
require "./renderer"
require "./session"
require "./input/controller"
require "./input/keymap"

module Obsctl
  module TUI
    # Interactive ANSI TUI application loop.
    class App
      def initialize(@config : Config::Config, @config_path : String)
        @renderer = Renderer.new
      end

      # Runs the TUI until the user quits and returns a process exit code.
      def run : Int32
        session = Session.new(@config, @config_path)
        input_controller = Input::Controller.new(Input::Keymap.new(@config.keymap), @config.ui.command_palette_prefix)
        model = session.start
        render(model_with_command_line(model, input_controller.command_line))
        input = Channel(String?).new

        spawn do
          read_input(input)
          input.send(nil)
        end

        loop do
          select
          when key = input.receive
            break unless key

            action = input_controller.handle(key)
            case action.kind
            when Input::ActionKind::Quit
              break
            when Input::ActionKind::Submit
              command = action.command
              next unless command

              result = session.execute_line(command)
              break if result.quit
              model = result.model
              render(model_with_command_line(model, input_controller.command_line))
            when Input::ActionKind::Render
              render(model_with_command_line(model, input_controller.command_line))
            when Input::ActionKind::None
            end
          when timeout(@config.ui.refresh_interval_ms.milliseconds)
            refreshed = session.poll_events
            if refreshed != model
              model = refreshed
              render(model_with_command_line(model, input_controller.command_line))
            end
          end
        end
        session.close
        0
      end

      private def render(model : Model) : Nil
        width, height = terminal_size
        @renderer.render_incremental(model, STDOUT, width, height)
      end

      private def read_input(input : Channel(String?)) : Nil
        if STDIN.tty?
          STDIN.raw { read_chars(input) }
        else
          read_chars(input)
        end
      end

      private def read_chars(input : Channel(String?)) : Nil
        while char = STDIN.read_char
          input.send(char.to_s)
        end
      end

      private def model_with_command_line(model : Model, command_line : String) : Model
        Model.new(
          snapshot: model.snapshot,
          command_line: command_line,
          last_result: model.last_result,
          logs: model.logs
        )
      end

      private def terminal_size : Tuple(Int32, Int32)
        {
          ENV["COLUMNS"]?.try(&.to_i?) || Renderer::DEFAULT_WIDTH,
          ENV["LINES"]?.try(&.to_i?) || Renderer::DEFAULT_HEIGHT,
        }
      end
    end
  end
end
