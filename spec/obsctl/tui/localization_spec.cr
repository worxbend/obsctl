require "../../spec_helper"
require "../../../src/obsctl/tui/localization"
require "../../../src/obsctl/tui/widgets/header"
require "../../../src/obsctl/tui/widgets/connection"

describe Obsctl::TUI::Localization do
  it "resolves environment, config, case, and unsupported locales like Rust" do
    Obsctl::TUI::Localization.resolve("uk", nil).should eq("uk")
    Obsctl::TUI::Localization.resolve("en", " UK ").should eq("uk")
    Obsctl::TUI::Localization.resolve("fr", nil).should eq("en")
    Obsctl::TUI::Localization.resolve("uk", " ").should eq("uk")
  end

  it "renders the localized Rust header and unavailable vocabulary" do
    model = Obsctl::TUI::Model.new(locale: "uk", advanced_ui: false)
    model.connected_to_daemon = true
    model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
      connected: true,
      obs_studio_version: "30.1.0",
      obs_websocket_version: "5.0.0",
      current_scene: "Головна",
      scenes: [] of Obsctl::OBS::State::SceneState,
      audio_inputs: [] of Obsctl::OBS::State::AudioState,
      current_profile: "Потік"
    )
    header = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 100, 4))
    Obsctl::TUI::Widgets::Header.render(header.area, header, model)
    text = header.lines.join("\n")
    text.should contain("демон: з'єднано")
    text.should contain("OBS: з'єднано (v30.1.0)")
    text.should contain("сцена: Головна")
    text.should contain("профіль: Потік")

    model.connected_to_daemon = false
    unavailable = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 80, 14))
    Obsctl::TUI::Widgets::Connection.render_unavailable(unavailable.area, unavailable, model)
    localized = unavailable.lines.join("\n")
    localized.should contain("obsctl - демон недоступний")
    localized.should contain("сервер obsctl не запущено")
    localized.should contain("Натисніть R")
  end
end
