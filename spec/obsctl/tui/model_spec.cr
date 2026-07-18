require "../../spec_helper"
require "../../../src/obsctl/tui/model"

private def tui_snapshot
  Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "30.0.0",
    obs_websocket_version: "5.0.0",
    current_scene: "Main",
    scenes: [Obsctl::OBS::State::SceneState.new("Main", active: true), Obsctl::OBS::State::SceneState.new("Cam")],
    audio_inputs: [Obsctl::OBS::State::AudioState.new("Mic", muted: false, volume_percent: 80)]
  )
end

private def telemetry_snapshot(cpu : Float64, bitrate : Float64)
  tui_snapshot.copy_with(
    stats: Obsctl::OBS::State::ObsStats.new(cpu_usage_percent: cpu),
    stream_bitrate_kbps: bitrate
  )
end

describe Obsctl::TUI::FocusPanel do
  it "navigates the four-panel grid and stops at edges" do
    Obsctl::TUI::FocusPanel::Scenes.right.should eq(Obsctl::TUI::FocusPanel::Audio)
    Obsctl::TUI::FocusPanel::Audio.down.should eq(Obsctl::TUI::FocusPanel::Collections)
    Obsctl::TUI::FocusPanel::Collections.left.should eq(Obsctl::TUI::FocusPanel::Profiles)
    Obsctl::TUI::FocusPanel::Profiles.up.should eq(Obsctl::TUI::FocusPanel::Scenes)
    Obsctl::TUI::FocusPanel::Scenes.left.should eq(Obsctl::TUI::FocusPanel::Scenes)
  end
end

describe Obsctl::TUI::Model do
  it "previews audio volume without waiting for a server snapshot" do
    model = Obsctl::TUI::Model.new
    model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
      connected: true,
      obs_studio_version: nil,
      obs_websocket_version: nil,
      current_scene: nil,
      scenes: [] of Obsctl::OBS::State::SceneState,
      audio_inputs: [Obsctl::OBS::State::AudioState.new("Mic", volume_percent: 50)]
    )

    model.preview_audio_volume("Mic", 65)

    model.audio_inputs.first.volume_percent.should eq(65)
    model.audio_inputs.first.volume_mul.should eq(0.65)
  end

  it "clamps and moves focused list cursors" do
    model = Obsctl::TUI::Model.new
    model.snapshot = tui_snapshot
    model.scene_cursor = 99
    model.clamp_cursors
    model.scene_cursor.should eq(1)
    model.focused_scene.try(&.name).should eq("Cam")
    model.move_up
    model.focused_scene.try(&.name).should eq("Main")
  end

  it "excludes hidden scenes from navigation while retaining them in the snapshot" do
    model = Obsctl::TUI::Model.new
    model.snapshot = tui_snapshot.copy_with(scenes: [
      Obsctl::OBS::State::SceneState.new("Main", active: true),
      Obsctl::OBS::State::SceneState.new("Utility", hidden: true),
      Obsctl::OBS::State::SceneState.new("Cam"),
    ])
    model.clamp_cursors

    model.scenes.map(&.name).should eq(["Main", "Cam"])
    model.snapshot.not_nil!.scenes.map(&.name).should eq(["Main", "Utility", "Cam"])
    model.move_down
    model.focused_scene.try(&.name).should eq("Cam")
  end

  it "caps rolling logs at 200 entries" do
    model = Obsctl::TUI::Model.new
    210.times { |index| model.push_log(Obsctl::TUI::LogEntry.new(Obsctl::Runtime::LogLevel::Info, "line #{index}")) }
    model.logs.size.should eq(200)
    model.logs.first.message.should eq("line 10")
  end

  it "caps rolling CPU and bitrate telemetry at 32 samples" do
    model = Obsctl::TUI::Model.new
    40.times do |sample|
      model.snapshot = telemetry_snapshot(sample.to_f64, sample.to_f64 * 100)
      model.record_metric_sample
    end
    model.cpu_history.size.should eq(32)
    model.cpu_history.first.should eq(8.0)
    model.bitrate_history.last.should eq(3900.0)
  end

  it "reveals command results by Unicode grapheme" do
    model = Obsctl::TUI::Model.new
    model.set_last_result("Київ ✓")
    model.revealed_last_result(2).should eq("")
    model.anim.tick
    model.revealed_last_result(2).should eq("Ки")
  end

  it "cycles palette completions in both directions" do
    palette = Obsctl::TUI::CommandPaletteState.new(completions: ["/scene Main", "/scene Cam"])
    palette.cycle_next
    palette.input.should eq("/scene Main")
    palette.cycle_previous
    palette.input.should eq("/scene Cam")
  end
end
