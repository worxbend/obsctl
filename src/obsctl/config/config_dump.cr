require "./config"
require "../domain/errors"

module Obsctl
  module Config
    # Merges discovered OBS resources into existing user config.
    module ConfigDump
      # Preserves user aliases/shortcuts/groups, marks missing resources stale,
      # adds newly discovered resources, and validates collisions before write.
      def self.merge(config : Config, scene_names : Array(String), input_names : Array(String)) : Config
        scene_set = scene_names.to_set
        input_set = input_names.to_set

        scenes = config.scenes.map do |scene|
          SceneConfig.new(scene.name, scene.alias, scene.shortcut, scene.group, !scene_set.includes?(scene.name), scene.hidden)
        end
        known_scene_names = scenes.map(&.name).to_set
        scene_names.each do |name|
          next if known_scene_names.includes?(name)
          scenes << SceneConfig.new(name: name)
        end

        inputs = config.audio.inputs.map do |input|
          AudioInputConfig.new(input.name, input.alias, input.shortcut, input.kind, !input_set.includes?(input.name))
        end
        known_input_names = inputs.map(&.name).to_set
        input_names.each do |name|
          next if known_input_names.includes?(name)
          inputs << AudioInputConfig.new(name: name)
        end

        merged = Config.new(
          version: config.version,
          server: config.server,
          connection: config.connection,
          reconnect: config.reconnect,
          scenes: scenes,
          audio: AudioConfig.new(inputs),
          ui: config.ui,
          # Every field the merge does not touch must be carried across
          # verbatim: this object is handed straight to `ConfigWriter`, so
          # anything omitted here falls back to its default and is written over
          # the user's own value.
          keymap: config.keymap,
        )
        validate_conflicts!(merged)
        merged
      end

      private def self.validate_conflicts!(config : Config) : Nil
        validate_entry_conflicts!(config.scenes, "scene")
        validate_entry_conflicts!(config.audio.inputs, "audio input")
      end

      # Runs both conflict checks over both control kinds for one list.
      #
      # `T` is `SceneConfig` or `AudioInputConfig`; the two are unrelated types
      # that happen to expose the same `name`, `alias` and `shortcut`, which is
      # all these checks read, so a free type variable is enough to serve both.
      private def self.validate_entry_conflicts!(entries : Array(T), kind : String) : Nil forall T
        validate_duplicate_controls!(entries, kind, "alias", &.alias)
        validate_duplicate_controls!(entries, kind, "shortcut", &.shortcut)
        validate_control_name_collisions!(entries, kind, "alias", &.alias)
        validate_control_name_collisions!(entries, kind, "shortcut", &.shortcut)
      end

      private def self.validate_duplicate_controls!(entries : Array(T), kind : String, control_kind : String, & : T -> String?) : Nil forall T
        by_value = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
        entries.each do |entry|
          value = normalized(yield entry)
          next unless value
          by_value[value] << entry.name
        end

        by_value.each do |value, names|
          next unless names.size > 1
          raise Domain::ConfigInvalid.new("dump-config conflict: duplicate #{kind} #{control_kind} '#{value}' on #{names.join(", ")}")
        end
      end

      private def self.validate_control_name_collisions!(entries : Array(T), kind : String, control_kind : String, & : T -> String?) : Nil forall T
        names_by_value = Hash(String, String).new
        entries.each do |entry|
          names_by_value[entry.name.downcase] = entry.name
        end

        entries.each do |entry|
          value = normalized(yield entry)
          next unless value

          owner = entry.name
          conflicting_name = names_by_value[value]?
          next unless conflicting_name
          next if conflicting_name.downcase == owner.downcase

          raise Domain::ConfigInvalid.new("dump-config conflict: #{kind} #{control_kind} '#{value}' on #{owner} matches OBS #{kind} name #{conflicting_name}")
        end
      end

      private def self.normalized(value : String?) : String?
        return unless value
        stripped = value.strip
        return if stripped.empty?
        stripped.downcase
      end
    end
  end
end
