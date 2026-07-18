require "../../spec_helper"
require "../../../src/obsctl/tui/app"

describe Obsctl::TUI::App do
  it "applies subscription events, palette paste, and quit actions" do
    model = Obsctl::TUI::Model.new
    app = Obsctl::TUI::App.new(model: model)
    sender = ->(payload : Obsctl::IPC::CommandPayload) { Obsctl::IPC::Response.new("test", true, JSON.parse(%({"message":"ok"}))) }
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

  it "renders unavailable, dashboard, and settings views through CryTUI" do
    model = Obsctl::TUI::Model.new(advanced_ui: false)
    app = Obsctl::TUI::App.new(model: model)
    backend = CryTUI::TestBackend.new(100, 40)
    terminal = CryTUI::Terminal.new(backend)

    app.render(terminal)
    backend.buffer.lines.join("\n").should contain("SERVER UNAVAILABLE")

    model.connected_to_daemon = true
    app.render(terminal)
    backend.buffer.lines.join("\n").should contain("BROADCAST COMMAND CENTER")

    model.view = Obsctl::TUI::View::Settings
    app.render(terminal)
    backend.buffer.lines.join("\n").should contain("THEME SETTINGS")
  end
end
