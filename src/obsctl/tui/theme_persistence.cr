require "../config/config"
require "../config/config_loader"
require "../config/config_writer"
require "./theme"

module Obsctl
  module TUI
    module ThemePersistence
      extend self

      def save(path : String?, theme : Theme) : String
        return "theme applied (no config file to persist to)" unless path
        config = Config::ConfigLoader.new.load_lenient(path)
        ui = config.ui
        config.ui = Config::UiConfig.new(
          refresh_interval_ms: ui.refresh_interval_ms,
          command_palette_prefix: ui.command_palette_prefix,
          advanced_ui: ui.advanced_ui,
          show_icons: ui.show_icons,
          theme: theme.id,
          custom_theme: ui.custom_theme,
          locale: ui.locale
        )
        Config::ConfigWriter.new.write(path, config, backup: File.exists?(path))
        "theme set: #{theme.id}"
      rescue ex
        "theme applied, but saving config failed: #{ex.message}"
      end
    end
  end
end
