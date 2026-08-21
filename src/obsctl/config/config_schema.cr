require "./config"
require "../domain/errors"

module Obsctl
  module Config
    # Validates loaded config and returns safe warnings for non-fatal issues.
    module ConfigSchema
      # Raises `Domain::ConfigInvalid` when config values would make runtime
      # behavior ambiguous, unsafe, or impossible.
      def self.validate!(config : Config) : Nil
        raise Domain::ConfigInvalid.new("unsupported config version: #{config.version}") unless config.version == 1
        config.connection.validate!
        if socket_path = config.server.socket_path
          raise Domain::ConfigInvalid.new("server.socket_path cannot be blank") if socket_path.blank?
        end
        if pid_file = config.server.pid_file
          raise Domain::ConfigInvalid.new("server.pid_file cannot be blank") if pid_file.blank?
        end
        config.reconnect.validate!
        config.ui.validate!

        duplicates(config.scenes.compact_map(&.alias), "duplicate scene alias")
        duplicates(config.scenes.compact_map(&.shortcut), "duplicate scene shortcut")
        duplicates(config.audio.inputs.compact_map(&.alias), "duplicate audio alias")
        duplicates(config.audio.inputs.compact_map(&.shortcut), "duplicate audio shortcut")
      end

      # Returns secret-safe warnings for valid configs that still deserve user
      # attention, such as plaintext password storage.
      def self.warnings(config : Config) : Array(String)
        warnings = [] of String
        if password = config.connection.password
          unless password.empty?
            warnings << "plaintext connection.password is configured; prefer connection.password_env so secrets stay out of config files"
          end
        end
        if locale = config.ui.locale
          unless {"en", "uk"}.includes?(locale.downcase)
            warnings << "ui.locale '#{locale}' is not supported (supported: en, uk); falling back to en"
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
