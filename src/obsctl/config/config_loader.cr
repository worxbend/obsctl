require "./config"
require "./config_schema"
require "../domain/errors"

module Obsctl
  module Config
    class ConfigLoader
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
