require "../../spec_helper"
require "../../../src/obsctl/tui/completion"

private def completion_model
  model = Obsctl::TUI::Model.new
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: nil,
    obs_websocket_version: nil,
    current_scene: "Main",
    scenes: [
      Obsctl::OBS::State::SceneState.new("Main"),
      Obsctl::OBS::State::SceneState.new("Media", alias: "m2"),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new("Mic"),
      Obsctl::OBS::State::AudioState.new("Music", alias: "m-bg"),
    ]
  )
  model.profiles = ["Default", "Streaming"]
  model.scene_collections = ["Podcast", "Gaming"]
  model
end

describe Obsctl::TUI::Completion do
  it "completes command prefixes with exact matches first" do
    model = completion_model
    Obsctl::TUI::Completion.compute("/sc", model).should eq(["/scene"])
    Obsctl::TUI::Completion.compute("/REC", model).should eq(["/rec", "/reconnect"])
  end

  it "completes scene names and aliases case-insensitively" do
    results = Obsctl::TUI::Completion.compute("/SCENE m", completion_model)
    results.should eq(["/SCENE m2", "/SCENE Main", "/SCENE Media"])
  end

  it "completes audio names and aliases" do
    results = Obsctl::TUI::Completion.compute("/mute m", completion_model)
    results.should eq(["/mute m-bg", "/mute Mic", "/mute Music"])
  end

  it "completes profiles and collections from IPC state" do
    Obsctl::TUI::Completion.compute("/profile s", completion_model).should eq(["/profile Streaming"])
    Obsctl::TUI::Completion.compute("/collection g", completion_model).should eq(["/collection Gaming"])
  end

  it "returns no argument completions for unrelated commands" do
    Obsctl::TUI::Completion.compute("/stream something", completion_model).should be_empty
  end
end
