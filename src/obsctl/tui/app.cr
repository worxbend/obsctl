require "./model"
require "./renderer"
require "./session"

module Obsctl
  module TUI
    class App
      def initialize(@config : Config::Config, @config_path : String)
        @renderer = Renderer.new
      end

      def run : Int32
        session = Session.new(@config, @config_path)
        model = session.start
        @renderer.render(model)
        input = Channel(String?).new

        spawn do
          STDIN.each_line { |line| input.send(line) }
          input.send(nil)
        end

        loop do
          select
          when line = input.receive
            break unless line

            result = session.execute_line(line.strip)
            break if result.quit
            model = result.model
            @renderer.render(model)
          when timeout(@config.ui.refresh_interval_ms.milliseconds)
            refreshed = session.poll_events
            if refreshed != model
              model = refreshed
              @renderer.render(model)
            end
          end
        end
        session.close
        0
      end
    end
  end
end
