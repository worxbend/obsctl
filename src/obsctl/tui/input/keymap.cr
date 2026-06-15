require "../../config/config"

module Obsctl
  module TUI
    module Input
      # Runtime keymap predicates backed by config.
      class Keymap
        def initialize(@config : Config::KeymapConfig)
        end

        # Returns true when `key` is bound to quit.
        def quit?(key : String) : Bool
          @config.quit.includes?(key)
        end

        # Returns true when `key` opens the command palette.
        def command_palette?(key : String) : Bool
          @config.command_palette.includes?(key)
        end

        # Returns true when `key` triggers reload-config.
        def reload_config?(key : String) : Bool
          @config.reload_config.includes?(key)
        end

        # Returns true when `key` triggers dump-config.
        def dump_config?(key : String) : Bool
          @config.dump_config.includes?(key)
        end
      end
    end
  end
end
