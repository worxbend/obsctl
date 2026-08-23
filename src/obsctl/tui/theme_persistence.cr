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
        # `copy_with` rather than a hand-listed `UiConfig.new`: picking a theme
        # must not touch any other dashboard setting, and rebuilding the struct
        # here would mean re-listing every field, so a field added later and
        # forgotten here would have its default written over the user's value.
        config.ui = config.ui.copy_with(theme: theme.id)
        Config::ConfigWriter.new.write(path, config, backup: File.exists?(path))
        "theme set: #{theme.id}"
      rescue ex
        "theme applied, but saving config failed: #{ex.message}"
      end
    end
  end
end
