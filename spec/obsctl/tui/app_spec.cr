require "../../spec_helper"
require "../../../src/obsctl/tui/app"

describe Obsctl::TUI::App do
  it "builds the runtime model from ui config" do
    config = Obsctl::Config::Config.new(ui: Obsctl::Config::UiConfig.new(
      theme: "custom",
      show_icons: false,
      advanced_ui: false,
      custom_theme: Obsctl::Config::CustomThemeConfig.new(accent: "#010203")
    ))

    app = Obsctl::TUI::App.from_config(config)
    app.model.theme.id.should eq("custom")
    app.model.theme.accent.should eq(CryTUI::Color.rgb(1, 2, 3))
    app.model.show_icons.should be_false
    app.model.advanced_ui.should be_false
    app.model.command_palette_prefix.should eq("/")
  end

  it "applies the configured TUI locale" do
    config = Obsctl::Config::Config.new(ui: Obsctl::Config::UiConfig.new(locale: "uk"))
    Obsctl::TUI::App.from_config(config).model.locale.should eq("uk")
  end

  it "clamps the runtime refresh to Rust's 50ms floor" do
    config = Obsctl::Config::Config.new(ui: Obsctl::Config::UiConfig.new(refresh_interval_ms: 10))
    Obsctl::TUI::App.from_config(config).refresh.should eq(50.milliseconds)
  end

  it "applies subscription events, palette paste, and quit actions" do
    model = Obsctl::TUI::Model.new
    app = Obsctl::TUI::App.new(model: model)
    sender = ->(_payload : Obsctl::IPC::CommandPayload) { Obsctl::IPC::Response.new("test", true, JSON.parse(%({"message":"ok"}))) }
    dispatcher = Obsctl::TUI::Dispatcher.new(model, sender)

    state = JSON.parse(%({"connected":true,"obs_studio_version":"30","obs_websocket_version":"5","current_scene":"Main","scenes":[{"name":"Main","active":true}],"audio_inputs":[],"output":{"streaming":false,"recording":false},"updated_at":"2026-07-18T12:00:00Z"}))
    app.process(Obsctl::TUI::SubscriptionMessage.new(0, event: Obsctl::IPC::Event.new("state", state)), dispatcher).should be_false
    model.current_scene.should eq("Main")

    model.command_palette.active = true
    model.command_palette.input = "/scene "
    app.process(CryTUI::PasteEvent.new("Main\u0000"), dispatcher).should be_false
    model.command_palette.input.should eq("/scene Main")
    app.process(CryTUI::KeyEvent.character('q'), dispatcher).should be_false
    model.command_palette.input.should eq("/scene Mainq")
    model.command_palette.active = false
    app.process(CryTUI::KeyEvent.character('q'), dispatcher).should be_true
  end

  it "restarts the result reveal animation when a subscription disconnects" do
    model = Obsctl::TUI::Model.new
    model.anim.frame = 42_u64
    app = Obsctl::TUI::App.new(model: model)
    sender = ->(_payload : Obsctl::IPC::CommandPayload) { Obsctl::IPC::Response.new("test", true) }
    dispatcher = Obsctl::TUI::Dispatcher.new(model, sender)

    app.process(Obsctl::TUI::SubscriptionMessage.new(0, error: "daemon gone"), dispatcher)

    model.connected_to_daemon.should be_false
    model.last_result.should eq("daemon gone")
    model.last_result_frame.should eq(42_u64)
  end

  it "quits when terminal input closes instead of ticking forever" do
    model = Obsctl::TUI::Model.new
    app = Obsctl::TUI::App.new(model: model)
    sender = ->(_payload : Obsctl::IPC::CommandPayload) { Obsctl::IPC::Response.new("test", true) }
    dispatcher = Obsctl::TUI::Dispatcher.new(model, sender)

    app.process(Obsctl::TUI::InputClosed.new, dispatcher).should be_true
    app.process(Obsctl::TUI::ResizeDetected.new, dispatcher).should be_false
  end

  it "renders unavailable, dashboard, and settings views through CryTUI" do
    model = Obsctl::TUI::Model.new(advanced_ui: false)
    app = Obsctl::TUI::App.new(model: model)
    backend = CryTUI::TestBackend.new(100, 40)
    terminal = CryTUI::Terminal.new(backend)

    app.render(terminal)
    backend.buffer.lines.join("\n").should contain("obsctl - daemon unavailable")

    model.connected_to_daemon = true
    app.render(terminal)
    backend.buffer.lines.join("\n").should contain("BROADCAST COMMAND CENTER")

    model.view = Obsctl::TUI::View::Settings
    app.render(terminal)
    settings = backend.buffer.lines.join("\n")
    settings.should contain("Settings // Appearance")
    settings.should contain("Themes // 29 palettes")
    settings.should contain("Preview: Ember")
  end

  it "reflows the dashboard through repeated terminal shrink and expansion" do
    model = Obsctl::TUI::Model.new(advanced_ui: false)
    model.connected_to_daemon = true
    app = Obsctl::TUI::App.new(model: model)
    backend = CryTUI::TestBackend.new(120, 40)
    terminal = CryTUI::Terminal.new(backend)

    app.render(terminal)
    backend.resize(40, 12)
    app.render(terminal)
    backend.buffer.area.should eq(CryTUI::Rect.new(0, 0, 40, 12))
    compact_lines = backend.buffer.lines
    compact_lines.size.should eq(12)
    compact_lines.max_of(&.size).should be <= 40

    backend.resize(90, 28)
    app.render(terminal)
    backend.buffer.area.should eq(CryTUI::Rect.new(0, 0, 90, 28))
    backend.buffer.lines.size.should eq(28)
    backend.buffer.lines.join("\n").should contain("BROADCAST COMMAND CENTER")
  end
end
