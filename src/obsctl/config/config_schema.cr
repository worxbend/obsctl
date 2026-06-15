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
        if socket_path = config.server.socket_path
          raise Domain::ConfigInvalid.new("server.socket_path cannot be blank") if socket_path.blank?
        end
        if pid_file = config.server.pid_file
          raise Domain::ConfigInvalid.new("server.pid_file cannot be blank") if pid_file.blank?
        end
        if config.reconnect.initial_delay_ms < 0
          raise Domain::ConfigInvalid.new("reconnect.initial_delay_ms cannot be negative")
        end
        if config.reconnect.max_delay_ms < 0
          raise Domain::ConfigInvalid.new("reconnect.max_delay_ms cannot be negative")
        end
        if config.reconnect.max_delay_ms < config.reconnect.initial_delay_ms
          raise Domain::ConfigInvalid.new("reconnect.max_delay_ms must be greater than or equal to initial_delay_ms")
        end
        if config.reconnect.multiplier < 1.0
          raise Domain::ConfigInvalid.new("reconnect.multiplier must be at least 1.0")
        end
        if config.reconnect.jitter_ms < 0
          raise Domain::ConfigInvalid.new("reconnect.jitter_ms cannot be negative")
        end

        duplicates(config.scenes.compact_map(&.alias), "duplicate scene alias")
        duplicates(config.scenes.compact_map(&.shortcut), "duplicate scene shortcut")
        duplicates(config.audio.inputs.compact_map(&.alias), "duplicate audio alias")
        duplicates(config.audio.inputs.compact_map(&.shortcut), "duplicate audio shortcut")
      end

      def self.warnings(config : Config) : Array(String)
        warnings = [] of String
        if password = config.connection.password
          unless password.empty?
            warnings << "plaintext connection.password is configured; prefer connection.password_env so secrets stay out of config files"
          end
        end
        warnings
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
