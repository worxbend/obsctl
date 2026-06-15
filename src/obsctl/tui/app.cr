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

        STDIN.each_line do |line|
          result = session.execute_line(line.strip)
          break if result.quit
          model = result.model
          @renderer.render(model)
        end
        session.close
        0
      end
    end
  end
end
