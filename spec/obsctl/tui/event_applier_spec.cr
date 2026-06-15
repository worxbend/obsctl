require "../../spec_helper"
require "../../../src/obsctl/tui/event_applier"

private def applier_snapshot
  Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.4.0",
    current_scene: "Main Camera",
    scenes: [
      Obsctl::OBS::State::SceneState.new(name: "Main Camera", alias: "main", shortcut: "1", active: true),
      Obsctl::OBS::State::SceneState.new(name: "BRB", alias: "brb", shortcut: "2", active: false),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new(name: "Mic/Aux", alias: "mic", shortcut: "m", muted: false, volume_mul: 0.7, volume_db: -3.0, volume_percent: 70),
    ]
  )
end

private def applier_event(type : String, data)
  Obsctl::OBS::Protocol::Event.new(type, JSON.parse(data.to_json))
end

describe Obsctl::TUI::EventApplier do
  it "marks the current scene active" do
    updated = Obsctl::TUI::EventApplier.apply(applier_snapshot, applier_event("CurrentProgramSceneChanged", {"sceneName" => "BRB"}))

    updated.current_scene.should eq("BRB")
    updated.scenes.find { |scene| scene.name == "Main Camera" }.try(&.active).should eq(false)
    updated.scenes.find { |scene| scene.name == "BRB" }.try(&.active).should eq(true)
  end

  it "updates input mute and volume events" do
    muted = Obsctl::TUI::EventApplier.apply(applier_snapshot, applier_event("InputMuteStateChanged", {"inputName" => "Mic/Aux", "inputMuted" => true}))
    volume = Obsctl::TUI::EventApplier.apply(muted, applier_event("InputVolumeChanged", {"inputName" => "Mic/Aux", "inputVolumeMul" => 0.42, "inputVolumeDb" => -9.0}))

    volume.audio_inputs.first.muted.should eq(true)
    volume.audio_inputs.first.volume_mul.should eq(0.42)
    volume.audio_inputs.first.volume_db.should eq(-9.0)
    volume.audio_inputs.first.volume_percent.should eq(42)
  end
end
