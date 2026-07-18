require "../../spec_helper"
require "../../../src/obsctl/tui/dispatcher"

private def dispatcher_fixture(volume_debounce : Time::Span = 10.milliseconds)
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
  {model, sent, Obsctl::TUI::Dispatcher.new(model, sender, volume_debounce: volume_debounce)}
end

private def wait_for_volume_command(sent : Array(Obsctl::IPC::CommandPayload), timeout = 1.second)
  deadline = Time.instant + timeout
  until sent.any?(&.name.==("set_volume"))
    raise "timed out waiting for debounced volume command" if Time.instant >= deadline
    Fiber.yield
  end
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
    model.focused_audio.not_nil!.volume_percent.should eq(55)
    wait_for_volume_command(sent)
    sent.map(&.name).should eq(["set_scene", "toggle_mute", "set_volume"])
    sent.last.target.should eq("Mic")
    sent.last.percent.should eq(55)
  end

  it "renders rapid volume changes immediately and sends only the trailing value" do
    model, sent, dispatcher = dispatcher_fixture(20.milliseconds)
    model.focus = Obsctl::TUI::FocusPanel::Audio

    6.times do
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::VolumeUp))
    end

    model.focused_audio.not_nil!.volume_percent.should eq(80)
    sent.should be_empty
    wait_for_volume_command(sent)
    sent.size.should eq(1)
    sent.first.target.should eq("Mic")
    sent.first.percent.should eq(80)
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

  it "forwards reconnect aliases and guarded server shutdown" do
    model, sent, dispatcher = dispatcher_fixture
    ["/reconnect", "/connect", "/shutdown-server"].each do |command|
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette))
      model.command_palette.input = command
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteSubmit))
    end
    sent.map(&.name).should eq(["reconnect_obs", "reconnect_obs", "shutdown_server"])
  end

  it "maps status to the Rust snapshot payload" do
    model, sent, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette))
    model.command_palette.input = "/status"
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteSubmit))

    sent.last.name.should eq("get_snapshot")
  end

  it "handles help, themes, quit, retry, and settings locally" do
    model, _, dispatcher = dispatcher_fixture
    ["/themes", "/theme", "/settings"].each do |command|
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette))
      model.command_palette.input = command
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteSubmit))
      model.view.should eq(Obsctl::TUI::View::Settings)
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::CloseSettings))
    end
    retry = dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::RetryConnect))
    retry.retry_subscription.should be_true
    retry.message.should eq("Reconnected to daemon.")
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::Quit)).quit.should be_true
  end
end
