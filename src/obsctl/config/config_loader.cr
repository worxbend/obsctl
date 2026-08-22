require "./config"
require "./config_schema"
require "../domain/errors"

module Obsctl
  module Config
    # Loads and validates YAML config files from disk.
    class ConfigLoader
      # Reads `path`, parses YAML, and validates the resulting config.
      def load(path : String) : Config
        raise Domain::ConfigNotFound.new(path) unless File.exists?(path)
        config = Config.from_yaml(File.read(path))
        ConfigSchema.validate!(config)
        config
      rescue ex : YAML::ParseException
        raise Domain::ConfigInvalid.new("invalid YAML: #{ex.message}")
      end

      # Reads `path` without validating it, and falls back to the built-in
      # defaults when the file is absent.
      #
      # The thin clients — the TUI, socket-path lookup, theme persistence —
      # need the local appearance and socket settings but must not require the
      # daemon's OBS password environment, which `load` would enforce through
      # `ConfigSchema.validate!`. A missing file is not an error for them
      # either: they run against the defaults. Parse failures are still raised,
      # because each caller wants to report them differently.
      def load_lenient(path : String) : Config
        return Config.default unless File.exists?(path)

        Config.from_yaml(File.read(path))
      end
    end
  end
end
