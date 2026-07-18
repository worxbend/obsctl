require "../../spec_helper"
require "../../../src/obsctl/tui/theme_persistence"

describe Obsctl::TUI::ThemePersistence do
  it "persists only the selected theme while preserving every other ui field" do
    path = File.join(Dir.tempdir, "obsctl-theme-#{Random.rand(1_000_000)}.yml")
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
      ui: Obsctl::Config::UiConfig.new(
        refresh_interval_ms: 333,
        command_palette_prefix: ":",
        advanced_ui: false,
        show_icons: false,
        theme: "claude",
        locale: "uk"
      )
    )
    Obsctl::Config::ConfigWriter.new.write(path, config, backup: false)

    Obsctl::TUI::ThemePersistence.save(path, Obsctl::TUI::Theme::NORD).should eq("theme set: nord")
    persisted = Obsctl::Config::Config.from_yaml(File.read(path))
    persisted.ui.theme.should eq("nord")
    persisted.ui.refresh_interval_ms.should eq(333)
    persisted.ui.command_palette_prefix.should eq(":")
    persisted.ui.advanced_ui.should be_false
    persisted.ui.show_icons.should be_false
    persisted.ui.locale.should eq("uk")
  ensure
    File.delete(path) if path && File.exists?(path)
    Dir.glob("#{path}.bak.*").each { |backup| File.delete(backup) } if path
  end

  it "reports no persistence target without treating theme application as failure" do
    Obsctl::TUI::ThemePersistence.save(nil, Obsctl::TUI::Theme::NORD)
      .should eq("theme applied (no config file to persist to)")
  end
end
