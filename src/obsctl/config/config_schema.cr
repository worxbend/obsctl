require "./config"
require "../domain/errors"

module Obsctl
  module Config
    module ConfigSchema
      def self.validate!(config : Config) : Nil
        raise Domain::ConfigInvalid.new("unsupported config version: #{config.version}") unless config.version == 1
        raise Domain::ConfigInvalid.new("host cannot be empty") if config.connection.host.blank?
        unless 1 <= config.connection.port <= 65_535
          raise Domain::ConfigInvalid.new("port must be from 1 to 65535")
        end
        if env = config.connection.password_env
          unless env.empty? || ENV.has_key?(env)
            raise Domain::ConfigInvalid.new("password env var is missing: #{env}")
          end
        end
        if config.ui.refresh_interval_ms <= 0
          raise Domain::ConfigInvalid.new("refresh_interval_ms must be positive")
        end

        duplicates(config.scenes.compact_map(&.alias), "duplicate scene alias")
        duplicates(config.scenes.compact_map(&.shortcut), "duplicate scene shortcut")
        duplicates(config.audio.inputs.compact_map(&.alias), "duplicate audio alias")
        duplicates(config.audio.inputs.compact_map(&.shortcut), "duplicate audio shortcut")
      end

      private def self.duplicates(values : Array(String), message : String) : Nil
        seen = Set(String).new
        values.each do |value|
          next if value.empty?
          raise Domain::ConfigInvalid.new("#{message}: #{value}") unless seen.add?(value)
        end
      end
    end
  end
end
