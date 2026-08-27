require "../../spec_helper"
require "../../support/scene_profiles"
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

private def telemetry_snapshot(cpu : Float64, bitrate : Float64, fps : Float64 = 60.0)
  tui_snapshot.copy_with(
    stats: Obsctl::OBS::State::ObsStats.new(cpu_usage_percent: cpu, active_fps: fps),
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
    # The editor is the one surface that has to see the hidden scene, because
    # it is the only place a hidden scene can be brought back.
    model.all_scenes.map(&.name).should eq(["Main", "Utility", "Cam"])
  end

  it "lets an active scene profile decide the whole visible list" do
    model = Obsctl::TUI::Model.new
    model.snapshot = tui_snapshot.copy_with(scenes: [
      Obsctl::OBS::State::SceneState.new("Main", active: true),
      Obsctl::OBS::State::SceneState.new("Utility", hidden: true),
      Obsctl::OBS::State::SceneState.new("Cam"),
    ])
    set_scene_profiles(
      model,
      Obsctl::TUI::SceneProfiles.empty.upsert("streaming", Set{"Cam"}).activate("streaming"),
      baseline_hidden: ["Utility"]
    )

    # The profile is the complete answer: `Cam` goes because the profile hides
    # it, and `Utility` comes back even though the config marks it hidden.
    model.scenes.map(&.name).should eq(["Main", "Utility"])
  end

  it "falls back to the hidden flag when the active profile is not configured" do
    # A hand-edited config file naming a profile that is not there has to
    # degrade to what the dashboard did before profiles existed, rather than to
    # an empty scene list.
    model = Obsctl::TUI::Model.new
    model.snapshot = tui_snapshot.copy_with(scenes: [
      Obsctl::OBS::State::SceneState.new("Main", active: true),
      Obsctl::OBS::State::SceneState.new("Utility", hidden: true),
    ])
    set_scene_profiles(model, Obsctl::TUI::SceneProfiles.empty.activate("missing"), baseline_hidden: ["Utility"])

    model.scenes.map(&.name).should eq(["Main"])
  end

  it "clamps the scene profile editor cursor against the unfiltered scene list" do
    model = Obsctl::TUI::Model.new
    model.snapshot = tui_snapshot.copy_with(scenes: [
      Obsctl::OBS::State::SceneState.new("Main", active: true),
      Obsctl::OBS::State::SceneState.new("Utility", hidden: true),
      Obsctl::OBS::State::SceneState.new("Cam"),
    ])
    model.scene_profile_editor.cursor = 99
    model.clamp_cursors
    # Two if it were clamped to the visible scenes; the editor lists all three.
    model.scene_profile_editor.cursor.should eq(2)
  end

  it "puts show-every-scene first and marks it current while no profile is active" do
    model = Obsctl::TUI::Model.new
    model.snapshot = tui_snapshot
    set_scene_profiles(model, Obsctl::TUI::SceneProfiles.empty.upsert("streaming", Set{"Cam"}).upsert("editing", Set(String).new))

    entries = model.scene_profile_list_entries

    entries.map(&.name).should eq(["Show every scene", "streaming", "editing"])
    # The row that turns filtering off stands for no profile, which is what
    # tells the verbs on a row there is nothing to edit or delete.
    entries[0].profile.should be_nil
    entries[0].active.should be_true
    entries[1].active.should be_false
  end

  it "marks the saved profile that is in effect rather than the first row" do
    model = Obsctl::TUI::Model.new
    model.snapshot = tui_snapshot
    set_scene_profiles(model, Obsctl::TUI::SceneProfiles.empty.upsert("streaming", Set{"Cam"}).upsert("editing", Set(String).new).activate("editing"))

    entries = model.scene_profile_list_entries

    entries.map(&.active).should eq([false, false, true])
    entries[2].profile.try(&.name).should eq("editing")
  end

  it "labels rows by their own number and leaves a tenth profile unlabelled" do
    profiles = Obsctl::TUI::SceneProfiles.empty
    10.times { |index| profiles = profiles.upsert("profile #{index}", Set(String).new) }
    model = Obsctl::TUI::Model.new
    model.snapshot = tui_snapshot
    set_scene_profiles(model, profiles)

    entries = model.scene_profile_list_entries

    entries.map(&.label).should eq(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', nil])
    Obsctl::TUI::SceneProfileList.index_for(entries, '0').should eq(0)
    Obsctl::TUI::SceneProfileList.index_for(entries, '3').should eq(3)
    # The tenth profile carries no digit, so nothing resolves to it by key; the
    # cursor is how it is reached.
    Obsctl::TUI::SceneProfileList.index_for(entries, 'a').should be_nil
  end

  it "clamps the scene profile list cursor after profiles are removed" do
    model = Obsctl::TUI::Model.new
    model.snapshot = tui_snapshot
    set_scene_profiles(model, Obsctl::TUI::SceneProfiles.empty.upsert("streaming", Set{"Cam"}).upsert("editing", Set(String).new))
    model.scene_profile_list.cursor = 2

    set_scene_profiles(model, model.scene_profiles.delete("editing"))
    model.clamp_cursors

    # One row per profile plus the show-every-scene row, so two rows and a
    # cursor at index one.
    model.scene_profile_list.cursor.should eq(1)
  end

  it "caps rolling logs at 200 entries" do
    model = Obsctl::TUI::Model.new
    210.times { |index| model.push_log(Obsctl::TUI::LogEntry.new(Obsctl::Runtime::LogLevel::Info, "line #{index}")) }
    model.logs.size.should eq(200)
    model.logs.first.message.should eq("line 10")
  end

  it "caps rolling CPU, bitrate, and FPS telemetry at 32 samples" do
    model = Obsctl::TUI::Model.new
    40.times do |sample|
      model.snapshot = telemetry_snapshot(sample.to_f64, sample.to_f64 * 100, fps: 60.0 - sample)
      model.record_metric_sample
    end
    model.cpu_history.size.should eq(32)
    model.cpu_history.first.should eq(8.0)
    model.bitrate_history.last.should eq(3900.0)
    model.fps_history.size.should eq(32)
    model.fps_history.last.should eq(21.0)
  end

  it "reveals command results by Unicode grapheme" do
    model = Obsctl::TUI::Model.new
    model.set_last_result("Київ ✓")
    model.revealed_last_result(2).should eq("")
    model.anim.tick
    model.revealed_last_result(2).should eq("Ки")
  end

  it "holds a meter peak and lets it fall back on its own" do
    model = Obsctl::TUI::Model.new
    model.record_meter_level("Mic", 1.0)
    held = model.meter_peak("Mic").not_nil!
    held.should be_close(1.0, 0.0001)

    # A quieter reading leaves the hold where it was; the marker falls with the
    # clock rather than with the signal.
    10.times { model.anim.tick }
    model.record_meter_level("Mic", 0.001)
    faded = model.meter_peak("Mic").not_nil!
    faded.should be < held
    faded.should be_close(1.0 - 10 * Obsctl::TUI::Meter::PEAK_FALL_PER_FRAME, 0.0001)

    # A louder reading takes the hold back to the top.
    model.record_meter_level("Mic", 1.0)
    model.meter_peak("Mic").not_nil!.should be_close(1.0, 0.0001)
  end

  it "drops a meter peak once it has fallen all the way to the floor" do
    model = Obsctl::TUI::Model.new
    model.record_meter_level("Mic", 0.5)
    (2 + (1.0 / Obsctl::TUI::Meter::PEAK_FALL_PER_FRAME).to_i).times { model.anim.tick }
    model.meter_peak("Mic").should be_nil
  end

  it "cycles palette completions in both directions" do
    palette = Obsctl::TUI::CommandPaletteState.new(completions: ["/scene Main", "/scene Cam"])
    palette.cycle_next
    palette.input.should eq("/scene Main")
    palette.cycle_previous
    palette.input.should eq("/scene Cam")
  end
end

describe "cursor motions" do
  it "jumps and steps within the focused panel without leaving it" do
    model = Obsctl::TUI::Model.new
    model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
      connected: true,
      obs_studio_version: nil,
      obs_websocket_version: nil,
      current_scene: "A",
      scenes: [
        Obsctl::OBS::State::SceneState.new("A"),
        Obsctl::OBS::State::SceneState.new("B"),
        Obsctl::OBS::State::SceneState.new("C"),
      ],
      audio_inputs: [] of Obsctl::OBS::State::AudioState
    )

    model.move_bottom
    model.scene_cursor.should eq(2)
    model.move_by(5)
    model.scene_cursor.should eq(2)
    model.move_top
    model.scene_cursor.should eq(0)
    model.move_by(-5)
    model.scene_cursor.should eq(0)

    # An empty panel has nowhere to go rather than a negative cursor.
    model.focus = Obsctl::TUI::FocusPanel::Audio
    model.move_bottom
    model.audio_cursor.should eq(0)
  end
end
