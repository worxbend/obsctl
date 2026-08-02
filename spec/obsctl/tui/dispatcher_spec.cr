require "../../spec_helper"
require "../../../src/obsctl/tui/dispatcher"

private def dispatcher_fixture(volume_debounce : Time::Span = 10.milliseconds)
  model = Obsctl::TUI::Model.new
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: nil,
    obs_websocket_version: nil,
    current_scene: "Main",
    scenes: [
      Obsctl::OBS::State::SceneState.new("Main", active: true),
      Obsctl::OBS::State::SceneState.new("Cam"),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new("Mic", muted: false, volume_percent: 50),
      Obsctl::OBS::State::AudioState.new("Desktop", muted: true, volume_percent: 20),
    ],
    profiles: ["Default", "Streaming"],
    current_profile: "Default"
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
    sender = ->(_payload : Obsctl::IPC::CommandPayload) do
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

describe "pointer actions" do
  it "acts on the row the pointer named, not on whatever had focus" do
    model, sent, dispatcher = dispatcher_fixture
    # Focus and cursor deliberately point somewhere else entirely.
    model.focus = Obsctl::TUI::FocusPanel::Audio
    model.scene_cursor = 0

    dispatcher.handle(Obsctl::TUI::Action.new(
      Obsctl::TUI::ActionKind::PointerActivate,
      panel: Obsctl::TUI::FocusPanel::Scenes,
      index: 1
    ))

    model.focus.should eq(Obsctl::TUI::FocusPanel::Scenes)
    model.scene_cursor.should eq(1)
    sent.last.name.should eq("set_scene")
    sent.last.target.should eq("Cam")
  end

  it "moves focus and the cursor without sending anything" do
    model, sent, dispatcher = dispatcher_fixture

    dispatcher.handle(Obsctl::TUI::Action.new(
      Obsctl::TUI::ActionKind::PointerFocus,
      panel: Obsctl::TUI::FocusPanel::Profiles,
      index: 1
    ))

    model.focus.should eq(Obsctl::TUI::FocusPanel::Profiles)
    model.profile_cursor.should eq(1)
    sent.should be_empty
  end

  it "mutes the input under the pointer" do
    model, sent, dispatcher = dispatcher_fixture

    dispatcher.handle(Obsctl::TUI::Action.new(
      Obsctl::TUI::ActionKind::PointerToggleMute,
      panel: Obsctl::TUI::FocusPanel::Audio,
      index: 1
    ))

    model.audio_cursor.should eq(1)
    sent.last.name.should eq("toggle_mute")
    sent.last.target.should eq("Desktop")
  end

  it "clamps a row index that no longer exists" do
    model, sent, dispatcher = dispatcher_fixture

    dispatcher.handle(Obsctl::TUI::Action.new(
      Obsctl::TUI::ActionKind::PointerFocus,
      panel: Obsctl::TUI::FocusPanel::Scenes,
      index: 99
    ))

    model.scene_cursor.should eq(1)
    sent.should be_empty
  end
end

describe "pointer gain" do
  it "adjusts the input under the pointer and debounces one OBS command" do
    model, sent, dispatcher = dispatcher_fixture
    model.audio_cursor = 0

    # A wheel spun over the second input, which is not the selected one.
    3.times do
      dispatcher.handle(Obsctl::TUI::Action.new(
        Obsctl::TUI::ActionKind::PointerVolumeUp,
        panel: Obsctl::TUI::FocusPanel::Audio,
        index: 1
      ))
    end

    model.audio_cursor.should eq(1)
    # Redrawn immediately from 20%, three steps of five.
    model.audio_inputs[1].volume_percent.should eq(35)

    wait_for_volume_command(sent)
    volume = sent.select(&.name.==("set_volume"))
    volume.size.should eq(1)
    volume.first.target.should eq("Desktop")
    volume.first.percent.should eq(35)
  end

  it "stops at the ends of the range" do
    model, _, dispatcher = dispatcher_fixture

    25.times do
      dispatcher.handle(Obsctl::TUI::Action.new(
        Obsctl::TUI::ActionKind::PointerVolumeDown,
        panel: Obsctl::TUI::FocusPanel::Audio,
        index: 0
      ))
    end

    model.audio_inputs[0].volume_percent.should eq(0)
  end
end

describe "vim bindings" do
  it "clears the pending sequence on whatever the next action is" do
    model, _, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PendingSequence, sequence: "<leader>"))
    model.pending_sequence.should eq("<leader>")

    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PendingSequence, sequence: "<leader>f"))
    model.pending_sequence.should eq("<leader>f")

    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::FocusAudio))
    model.pending_sequence.should be_empty
    model.focus.should eq(Obsctl::TUI::FocusPanel::Audio)
  end

  it "jumps to the ends of the focused panel" do
    model, _, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::NavigateBottom))
    model.scene_cursor.should eq(1)
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::NavigateTop))
    model.scene_cursor.should eq(0)
  end

  it "steps by half the focused panel's visible rows" do
    model = Obsctl::TUI::Model.new
    model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
      connected: true,
      obs_studio_version: nil,
      obs_websocket_version: nil,
      current_scene: "Scene 00",
      scenes: (0..40).map { |index| Obsctl::OBS::State::SceneState.new("Scene #{index}") },
      audio_inputs: [] of Obsctl::OBS::State::AudioState
    )
    sender = ->(_payload : Obsctl::IPC::CommandPayload) do
      Obsctl::IPC::Response.new("test", true, JSON.parse(%({"message":"ok"})))
    end
    area = CryTUI::Rect.new(0, 0, 120, 40)
    dispatcher = Obsctl::TUI::Dispatcher.new(model, sender, viewport: -> { area })

    rows = Obsctl::TUI::DashboardLayout.compute(area, false).scenes.height - 2
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::NavigateHalfPageDown))
    model.scene_cursor.should eq(rows // 2)
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::NavigateHalfPageUp))
    model.scene_cursor.should eq(0)
  end
end

describe "vim command line" do
  it "opens with the key that was pressed and completes under that leader" do
    model, _, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette, ':'))
    model.command_palette.input.should eq(":")
    model.command_palette.completions.should contain(":scene")
  end

  it "runs a command typed after a colon" do
    model, sent, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette, ':'))
    ":scene Cam".each_char.skip(1).each do |character|
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteCharacter, character))
    end
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteSubmit))
    sent.map(&.name).should eq(["set_scene"])
    sent.first.target.should eq("Cam")
  end

  it "answers the vim spellings of quit and help" do
    _, _, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette, ':'))
    ["q", "qa", "wq", "quit"].each do |word|
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette, ':'))
      word.each_char { |character| dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteCharacter, character)) }
      dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteSubmit)).quit.should be_true
    end

    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette, ':'))
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteCharacter, 'h'))
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteSubmit)).message.not_nil!.should start_with("Commands:")
  end

  it "clears the line back to its leader and deletes by word" do
    model, _, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette, ':'))
    "scene Cam".each_char { |character| dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteCharacter, character)) }

    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteDeleteWord))
    model.command_palette.input.should eq(":scene ")
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteClearLine))
    model.command_palette.input.should eq(":")
  end

  it "takes a completion from a click" do
    model, _, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenPalette, '/'))
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PaletteCharacter, 's'))
    target = model.command_palette.completions[1]

    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PointerCompletion, index: 1))
    model.command_palette.input.should eq(target)
    model.command_palette.completion_index.should eq(1)
  end

  it "previews a clicked theme and applies the one already previewed" do
    model, _, dispatcher = dispatcher_fixture
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenSettings))

    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PointerSettingsSelect, index: 2))
    model.settings_cursor.should eq(2)
    model.theme.should eq(Obsctl::TUI::Theme::ALL[2])
    model.view.should eq(Obsctl::TUI::View::Settings)

    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PointerSettingsApply))
    model.view.should eq(Obsctl::TUI::View::Main)
    model.theme.should eq(Obsctl::TUI::Theme::ALL[2])
  end
end
