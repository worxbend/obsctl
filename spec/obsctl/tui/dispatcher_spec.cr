require "../../spec_helper"
require "../../../src/obsctl/tui/dispatcher"

private def dispatcher_fixture
  model = Obsctl::TUI::Model.new
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: nil,
    obs_websocket_version: nil,
    current_scene: "Main",
    scenes: [Obsctl::OBS::State::SceneState.new("Main", active: true)],
    audio_inputs: [Obsctl::OBS::State::AudioState.new("Mic", muted: false, volume_percent: 50)]
  )
  sent = [] of Obsctl::IPC::CommandPayload
  sender = ->(payload : Obsctl::IPC::CommandPayload) do
    sent << payload
    Obsctl::IPC::Response.new("test", true, JSON.parse(%({"message":"ok"})))
  end
  {model, sent, Obsctl::TUI::Dispatcher.new(model, sender)}
end

describe Obsctl::TUI::Dispatcher do
  it "updates local palette state and dynamic completions" do
    model, _, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette))
    model.command_palette.active.should be_true
    model.command_palette.input.should eq("/")
    model.command_palette.completions.should contain("/scene")
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteCharacter, 's'))
    model.command_palette.input.should eq("/s")
  end

  it "sends focused scene, mute, and bounded volume actions through IPC payloads" do
    model, sent, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::ActivateScene)).message.should eq("ok")
    model.focus = Obsctl::TUI::FocusPanel::Audio
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::ToggleMute))
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::VolumeUp))
    sent.map(&.name).should eq(["set_scene", "toggle_mute", "set_volume"])
    sent.last.target.should eq("Mic")
    sent.last.percent.should eq(55)
  end

  it "parses palette commands and formats remote errors" do
    model = Obsctl::TUI::Model.new
    sender = ->(payload : Obsctl::IPC::CommandPayload) do
      Obsctl::IPC::Response.new("test", false, nil, Obsctl::IPC::ErrorPayload.new(Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE, "OBS offline"))
    end
    dispatcher = Obsctl::TUI::Dispatcher.new(model, sender)
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette))
    model.command_palette.input = "/scene Main"
    outcome = dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteSubmit))
    outcome.message.should eq("error [OBS_UNAVAILABLE]: OBS offline")
    model.command_palette.active.should be_false
  end

  it "forwards stream and recording palette toggles" do
    model, sent, dispatcher = dispatcher_fixture
    ["/stream", "/rec"].each do |command|
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette))
      model.command_palette.input = command
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteSubmit))
    end
    sent.map(&.name).should eq(["toggle_stream", "toggle_record"])
  end

  it "handles help, themes, quit, retry, and settings locally" do
    model, _, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette))
    model.command_palette.input = "/themes"
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteSubmit))
    model.view.should eq(Obsctl::TUI::View::Settings)
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::CloseSettings))
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::RetryConnect)).retry_subscription.should be_true
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::Quit)).quit.should be_true
  end
end
