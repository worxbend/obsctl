require "../config/config"
require "../config/config_loader"
require "../config/config_writer"
require "./scene_presets"

module Obsctl
  module TUI
    # Reads scene presets out of a loaded config and writes edited ones back.
    #
    # Modelled on `ThemePersistence`, and load-bearing in the same four ways:
    # the read is lenient so the dashboard never demands the daemon's OBS
    # password environment, the write rebuilds `ui` through `copy_with` so no
    # other setting is lost, a backup is kept only when there was a file to
    # back up, and a failed write comes back as a status string rather than an
    # exception, because the caller is inside the render loop.
    module ScenePresetPersistence
      extend self

      def from_config(config : Config::Config) : ScenePresets
        presets = config.ui.scene_presets.presets.map do |preset|
          ScenePreset.new(preset.name, preset.hidden_scenes.to_set)
        end
        ScenePresets.new(presets, config.ui.scene_presets.active)
      end

      def save(path : String?, presets : ScenePresets) : String
        label = presets.active || "scene presets"
        return "scene preset applied (no config file to persist to)" unless path

        config = Config::ConfigLoader.new.load_lenient(path)
        config.ui = config.ui.copy_with(scene_presets: to_config(presets))
        Config::ConfigWriter.new.write(path, config, backup: File.exists?(path))
        "scene preset saved: #{label}"
      rescue ex
        "scene preset applied, but saving config failed: #{ex.message}"
      end

      # Scene names are sorted on the way out so saving the same preset twice
      # produces the same file: a `Set` has no order of its own, and an order
      # that wandered between writes would surface as a change in
      # `obsctl config diff` that the user never made.
      private def to_config(presets : ScenePresets) : Config::ScenePresetsConfig
        Config::ScenePresetsConfig.new(
          active: presets.active,
          presets: presets.presets.map do |preset|
            Config::ScenePresetConfig.new(name: preset.name, hidden_scenes: preset.hidden_scenes.to_a.sort!)
          end
        )
      end
    end
  end
end
