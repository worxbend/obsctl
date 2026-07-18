require "../../spec_helper"
require "../../../src/obsctl/tui/widgets/header"
require "../../../src/obsctl/tui/widgets/scenes"
require "../../../src/obsctl/tui/widgets/audio"
require "../../../src/obsctl/tui/widgets/connection"
require "../../../src/obsctl/tui/widgets/command_palette"

private def widget_model
  model = Obsctl::TUI::Model.new(theme: Obsctl::TUI::Theme::NORD)
  model.connected_to_daemon = true
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "30.1.0",
    obs_websocket_version: "5.0.0",
    current_scene: "Main",
    scenes: [
      Obsctl::OBS::State::SceneState.new("Main", alias: "m", shortcut: "1", active: true),
      Obsctl::OBS::State::SceneState.new("Cam", group: "Studio"),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new("Mic", alias: "mic", muted: false, volume_percent: 80),
      Obsctl::OBS::State::AudioState.new("Desktop", muted: true, volume_percent: 0),
    ]
  )
  model.profiles = ["Default"]
  model.current_profile = "Default"
  model.meter_levels["Mic"] = 0.1
  model
end

private def rendered_text(buffer : CryTUI::Buffer)
  buffer.lines.join("\n")
end

describe Obsctl::TUI::Widgets::Header do
  it "renders daemon, OBS, scene, profile, and frame status" do
    model = widget_model
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 110, 4))
    Obsctl::TUI::Widgets::Header.render(buffer.area, buffer, model)
    text = rendered_text(buffer)

    text.should contain("OBSCTL // BROADCAST COMMAND CENTER")
    text.should contain("obsctl")
    text.should contain("daemon connected")
    text.should contain("OBS: 30.1.0")
    text.should contain("scene: Main")
    text.should contain("profile: Default")
  end

  it "renders disconnected state without a snapshot" do
    model = Obsctl::TUI::Model.new(advanced_ui: false)
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 70, 4))
    Obsctl::TUI::Widgets::Header.render(buffer.area, buffer, model)
    rendered_text(buffer).should contain("daemon disconnected")
  end
end

describe Obsctl::TUI::Widgets::Scenes do
  it "renders scene metadata and highlights the selected row" do
    model = widget_model
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 64, 7))
    Obsctl::TUI::Widgets::Scenes.render(buffer.area, buffer, model)
    text = rendered_text(buffer)

    text.should contain("Scenes")
    text.should contain("Main (m) [1]")
    text.should contain("Cam")
    text.should contain("Studio")
    buffer[10, 1].style.background.should eq(model.theme.highlight_background)
  end

  it "renders an empty panel without selecting a row" do
    model = Obsctl::TUI::Model.new
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 40, 4))
    Obsctl::TUI::Widgets::Scenes.render(buffer.area, buffer, model)
    rendered_text(buffer).should contain("Scenes")
  end
end

describe Obsctl::TUI::Widgets::Audio do
  it "renders mute state, volume, alias, and logarithmic meter" do
    model = widget_model
    model.focus = Obsctl::TUI::FocusPanel::Audio
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 76, 8))
    Obsctl::TUI::Widgets::Audio.render(buffer.area, buffer, model)
    text = rendered_text(buffer)

    text.should contain("Audio Matrix")
    text.should contain("Mic (mic) 80%")
    text.should contain("Desktop 0%")
    text.should contain("dB")
    text.should contain("▰")
    buffer[12, 1].style.background.should eq(model.theme.highlight_background)
    buffer[12, 2].style.background.should eq(model.theme.highlight_background)
  end
end

describe Obsctl::TUI::Theme do
  it "resolves built-in themes and parses custom hex colors safely" do
    Obsctl::TUI::Theme.by_id("Nord").should eq(Obsctl::TUI::Theme::NORD)
    Obsctl::TUI::Theme.by_id("unknown").should eq(Obsctl::TUI::Theme::CLAUDE)
    Obsctl::TUI::Theme.parse_hex("#12abEF").should eq(CryTUI::Color.rgb(0x12, 0xAB, 0xEF))
    Obsctl::TUI::Theme.parse_hex("nope").should be_nil
  end
end

describe Obsctl::TUI::Widgets::Connection do
  it "renders actionable server-unavailable guidance" do
    model = Obsctl::TUI::Model.new
    model.last_result = "connection refused"
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 72, 14))
    Obsctl::TUI::Widgets::Connection.render_unavailable(buffer.area, buffer, model)
    text = rendered_text(buffer)
    text.should contain("SERVER UNAVAILABLE")
    text.should contain("connection refused")
    text.should contain("obsctl server --headless")
    text.should contain("systemctl --user enable --now obsctl.service")
  end
end

describe Obsctl::TUI::Widgets::CommandPalette do
  it "renders active input, cursor, result reveal, and completions" do
    model = widget_model
    model.command_palette.active = true
    model.command_palette.input = "/scene M"
    model.command_palette.completions = ["/scene Main", "/scene Media"]
    model.command_palette.completion_index = 1
    model.set_last_result("scene changed")
    model.anim.tick
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 100, 5))
    Obsctl::TUI::Widgets::CommandPalette.render(buffer.area, buffer, model)
    text = rendered_text(buffer)
    text.should contain("Command Palette")
    text.should contain("/scene M")
    text.should contain("[/scene Main]")
    text.should contain("[/scene Media]")
    text.should contain("sce")
  end
end
