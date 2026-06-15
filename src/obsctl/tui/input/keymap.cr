require "../../config/config"

module Obsctl
  module TUI
    module Input
      class Keymap
        def initialize(@config : Config::KeymapConfig)
        end

        def quit?(key : String) : Bool
          @config.quit.includes?(key)
        end

        def command_palette?(key : String) : Bool
          @config.command_palette.includes?(key)
        end
      end
    end
  end
end
