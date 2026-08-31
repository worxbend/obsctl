require "../../spec_helper"
require "../../../src/obsctl/cli/completions"
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
  model.snapshot = model.snapshot.not_nil!.copy_with(
    profiles: ["Default", "Streaming"],
    scene_collections: ["Podcast", "Gaming"],
    scene_profiles: [
      Obsctl::OBS::State::SceneProfileState.new("Solo", ["Media"]),
      Obsctl::OBS::State::SceneProfileState.new("brb", ["Main"]),
    ]
  )
  model
end

describe Obsctl::TUI::Completion do
  it "completes command prefixes with exact matches first" do
    model = completion_model
    # `scene` is a prefix of the scene-profile commands, so an exact match
    # leads and the longer spellings follow it in order.
    Obsctl::TUI::Completion.compute("/sc", model).should eq([
      "/scene", "/scene-profile", "/scene-profile-delete", "/scene-profile-off", "/scene-profiles",
    ])
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

  it "completes saved scene-profile names" do
    model = completion_model
    Obsctl::TUI::Completion.compute("/scene-profile ", model).should eq([
      "/scene-profile brb", "/scene-profile Solo",
    ])
    Obsctl::TUI::Completion.compute("/scene-profile-delete s", model).should eq(["/scene-profile-delete Solo"])
  end

  it "returns no argument completions for unrelated commands" do
    Obsctl::TUI::Completion.compute("/stream something", completion_model).should be_empty
  end

  # The shell scripts and the palette both read the argument kind off the same
  # command registry, so a kind the shell completes from live daemon state has
  # to be one the palette completes too. `/scene-profile <TAB>` offering
  # nothing while `obsctl scene-profile <TAB>` worked is the exact drift this
  # pins, and a missing arm in the palette's dispatch is how it happened.
  it "completes in the palette every kind the shell completions call live" do
    model = completion_model
    palette_specs = Obsctl::Domain::CommandRegistry.for_surface(Obsctl::Domain::CommandSurface::Palette)

    not_completed = Obsctl::CLI::Completions::SOURCES.keys.select do |kind|
      spec = palette_specs.find { |candidate| candidate.arguments.first? == kind }
      # A kind no palette command takes is not the palette's business.
      next false unless spec

      Obsctl::TUI::Completion.compute("/#{spec.name} ", model).empty?
    end

    not_completed.should be_empty
  end
end

describe "palette leaders" do
  it "completes a colon line as its slash equivalent" do
    model = completion_model
    Obsctl::TUI::Completion.compute(":sc", model).should eq([
      ":scene", ":scene-profile", ":scene-profile-delete", ":scene-profile-off", ":scene-profiles",
    ])
    Obsctl::TUI::Completion.compute(":scene m", model).should eq([":scene m2", ":scene Main", ":scene Media"])
  end
end
