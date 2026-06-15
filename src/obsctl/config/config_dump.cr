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
          SceneConfig.new(scene.name, scene.alias, scene.shortcut, scene.group, !scene_set.includes?(scene.name))
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
          ui: config.ui,
          scenes: scenes,
          audio: AudioConfig.new(inputs),
          keymap: config.keymap
        )
        validate_conflicts!(merged)
        merged
      end

      private def self.validate_conflicts!(config : Config) : Nil
        validate_scene_conflicts!(config.scenes)
        validate_audio_conflicts!(config.audio.inputs)
      end

      private def self.validate_scene_conflicts!(scenes : Array(SceneConfig)) : Nil
        validate_duplicate_controls!(
          scenes,
          "scene",
          "alias",
          ->(scene : SceneConfig) { scene.alias },
          ->(scene : SceneConfig) { scene.name }
        )
        validate_duplicate_controls!(
          scenes,
          "scene",
          "shortcut",
          ->(scene : SceneConfig) { scene.shortcut },
          ->(scene : SceneConfig) { scene.name }
        )
        validate_control_name_collisions!(
          scenes,
          "scene",
          "alias",
          ->(scene : SceneConfig) { scene.alias },
          ->(scene : SceneConfig) { scene.name }
        )
        validate_control_name_collisions!(
          scenes,
          "scene",
          "shortcut",
          ->(scene : SceneConfig) { scene.shortcut },
          ->(scene : SceneConfig) { scene.name }
        )
      end

      private def self.validate_audio_conflicts!(inputs : Array(AudioInputConfig)) : Nil
        validate_duplicate_controls!(
          inputs,
          "audio input",
          "alias",
          ->(input : AudioInputConfig) { input.alias },
          ->(input : AudioInputConfig) { input.name }
        )
        validate_duplicate_controls!(
          inputs,
          "audio input",
          "shortcut",
          ->(input : AudioInputConfig) { input.shortcut },
          ->(input : AudioInputConfig) { input.name }
        )
        validate_control_name_collisions!(
          inputs,
          "audio input",
          "alias",
          ->(input : AudioInputConfig) { input.alias },
          ->(input : AudioInputConfig) { input.name }
        )
        validate_control_name_collisions!(
          inputs,
          "audio input",
          "shortcut",
          ->(input : AudioInputConfig) { input.shortcut },
          ->(input : AudioInputConfig) { input.name }
        )
      end

      private def self.validate_duplicate_controls!(entries : Array(T), kind : String, control_kind : String, control_value : Proc(T, String?), entry_name : Proc(T, String)) : Nil forall T
        by_value = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
        entries.each do |entry|
          value = normalized(control_value.call(entry))
          next unless value
          by_value[value] << entry_name.call(entry)
        end

        by_value.each do |value, names|
          next unless names.size > 1
          raise Domain::ConfigInvalid.new("dump-config conflict: duplicate #{kind} #{control_kind} '#{value}' on #{names.join(", ")}")
        end
      end

      private def self.validate_control_name_collisions!(entries : Array(T), kind : String, control_kind : String, control_value : Proc(T, String?), entry_name : Proc(T, String)) : Nil forall T
        names_by_value = Hash(String, String).new
        entries.each do |entry|
          names_by_value[entry_name.call(entry).downcase] = entry_name.call(entry)
        end

        entries.each do |entry|
          value = normalized(control_value.call(entry))
          next unless value

          owner = entry_name.call(entry)
          conflicting_name = names_by_value[value]?
          next unless conflicting_name
          next if conflicting_name.downcase == owner.downcase

          raise Domain::ConfigInvalid.new("dump-config conflict: #{kind} #{control_kind} '#{value}' on #{owner} matches OBS #{kind} name #{conflicting_name}")
        end
      end

      private def self.normalized(value : String?) : String?
        return nil unless value
        stripped = value.strip
        return nil if stripped.empty?
        stripped.downcase
      end
    end
  end
end
