require "../../spec_helper"
require "../../../src/obsctl/tui/event_applier"

private def state_payload(scene = "Main")
  JSON.parse({
    connected:                true,
    obs_studio_version:       "30.0.0",
    obs_websocket_version:    "5.0.0",
    current_scene:            scene,
    scenes:                   [{name: scene, alias: nil, shortcut: nil, group: nil, active: true}],
    audio_inputs:             [{name: "Mic", muted: false, volume_mul: 0.8, volume_db: -2.0, volume_percent: 80}],
    output:                   {streaming: true, recording: false},
    profiles:                 ["Default", "Streaming"],
    current_profile:          "Default",
    scene_collections:        ["Podcast"],
    current_scene_collection: "Podcast",
    last_error:               nil,
    updated_at:               "2026-07-18T12:00:00Z",
  }.to_json)
end

describe Obsctl::TUI::EventApplier do
  it "applies state snapshots and extended dashboard fields" do
    model = Obsctl::TUI::Model.new
    Obsctl::TUI::EventApplier.apply(model, Obsctl::IPC::Event.new("state", state_payload)).should be_true
    model.connected_to_daemon.should be_true
    model.obs_connected?.should be_true
    model.streaming?.should be_true
    model.current_scene.should eq("Main")
    model.profiles.should eq(["Default", "Streaming"])
    model.current_scene_collection.should eq("Podcast")
  end

  it "starts a flash only when an established scene changes" do
    model = Obsctl::TUI::Model.new
    Obsctl::TUI::EventApplier.apply(model, Obsctl::IPC::Event.new("state", state_payload("Main")))
    model.scene_flash.should be_nil
    model.anim.tick
    Obsctl::TUI::EventApplier.apply(model, Obsctl::IPC::Event.new("state", state_payload("Cam")))
    model.scene_flash.should eq({"Cam", 1_u64})
  end

  it "appends structured Crystal server logs" do
    model = Obsctl::TUI::Model.new
    data = JSON.parse({level: "warn", code: "reconnect", message: "retrying", created_at: "2026-07-18T12:00:00Z"}.to_json)
    Obsctl::TUI::EventApplier.apply(model, Obsctl::IPC::Event.new("logs", data))
    model.logs.first.level.should eq(Obsctl::Runtime::LogLevel::Warn)
    model.logs.first.code.should eq("reconnect")
  end

  it "applies normalized meter events without requesting an immediate redraw" do
    model = Obsctl::TUI::Model.new
    data = JSON.parse({type: "InputVolumeMeters", inputs: [{name: "Mic", level: 0.75}]}.to_json)
    Obsctl::TUI::EventApplier.apply(model, Obsctl::IPC::Event.new("events", data)).should be_false
    model.meter_levels["Mic"].should eq(0.75)
  end

  it "ignores malformed snapshots without losing the previous state" do
    model = Obsctl::TUI::Model.new
    Obsctl::TUI::EventApplier.apply(model, Obsctl::IPC::Event.new("state", state_payload))
    Obsctl::TUI::EventApplier.apply(model, Obsctl::IPC::Event.new("state", JSON.parse(%({"broken":true}))))
    model.current_scene.should eq("Main")
  end
end
