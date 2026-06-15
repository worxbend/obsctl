require "./config"

module Obsctl
  module Config
    module ConfigDump
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

        Config.new(
          version: config.version,
          connection: config.connection,
          ui: config.ui,
          scenes: scenes,
          audio: AudioConfig.new(inputs),
          keymap: config.keymap
        )
      end
    end
  end
end
