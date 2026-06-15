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
    end
  end
end
