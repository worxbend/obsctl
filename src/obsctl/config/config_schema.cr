require "./config"
require "../domain/errors"
require "../domain/scene_profiles"

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
        validate_scene_profiles!(config)
      end

      # A profile with an unusable name cannot be selected or saved over, and
      # two profiles whose names differ only in case or padding would make
      # `active_scene_profile` ambiguous.
      #
      # Runs after the alias and shortcut checks above so that a config with
      # both faults reports the same one obsctl-rs reports first.
      private def self.validate_scene_profiles!(config : Config) : Nil
        config.scene_profiles.each do |profile|
          if error = Domain::SceneProfileNames.checked_name_error(profile.name)
            raise Domain::ConfigInvalid.new("scene profile name #{error}")
          end
          profile.hidden.each do |scene|
            if error = Domain::SceneProfileNames.checked_name_error(scene)
              raise Domain::ConfigInvalid.new("scene profile '#{profile.name}' hidden scene #{error}")
            end
          end
        end

        seen = Set(String).new
        config.scene_profiles.each do |profile|
          # A name that will not normalize was already reported above; skipping
          # it here avoids inventing a second message for the one fault.
          next unless normalized = Domain::SceneProfileNames.normalized_name(profile.name)
          # Reported with the name as written, so the user can find the line.
          raise Domain::ConfigInvalid.new("duplicate scene profile name: '#{profile.name}'") unless seen.add?(normalized)
        end
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
        warnings.concat(scene_profile_warnings(config))
        warnings
      end

      # Warnings rather than errors, both of them, because either one would
      # otherwise empty a scene list over a typo -- and a dashboard with no
      # scenes looks broken in a way that "every scene is visible" does not.
      private def self.scene_profile_warnings(config : Config) : Array(String)
        warnings = [] of String
        active = config.active_scene_profile
        if active && config.active_scene_profile_config.nil?
          warnings << "active scene profile '#{active}' is not defined; no scenes are hidden by a profile"
        end

        # Skipped entirely while `scenes:` is empty, which is what a fresh
        # `obsctl init` writes: with no configured scenes there is no ground
        # truth to check a profile against, so every profile would warn.
        return warnings if config.scenes.empty?

        known = config.scenes.compact_map { |scene| Domain::SceneProfileNames.normalized_name(scene.name) }.to_set
        config.scene_profiles.each do |profile|
          profile.hidden.each do |scene|
            next unless normalized = Domain::SceneProfileNames.normalized_name(scene)
            next if known.includes?(normalized)

            warnings << "scene profile '#{profile.name}' hides '#{scene}', which is not in the scenes list"
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
