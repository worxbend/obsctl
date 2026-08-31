require "../../spec_helper"

describe Obsctl::Domain::Aliases do
  it "resolves scene lookup by shortcut first" do
    entries = [
      Obsctl::Domain::TargetEntry.new(name: "Main Camera", alias: "main", shortcut: "1"),
    ]
    Obsctl::Domain::Aliases.resolve_scene(entries, "1").name.should eq("Main Camera")
  end

  it "resolves unconfigured live OBS scene and audio names" do
    none = [] of Obsctl::Domain::TargetEntry

    Obsctl::Domain::Aliases.resolve_scene(none, "Scene 2", ["Scene 1", "Scene 2"]).name.should eq("Scene 2")
    Obsctl::Domain::Aliases.resolve_audio(none, "desktop audio", ["Desktop Audio"]).name.should eq("Desktop Audio")
  end

  it "preserves configured aliases when live names are merged" do
    scenes = [Obsctl::Domain::TargetEntry.new("Main Camera", alias: "main")]
    inputs = [Obsctl::Domain::TargetEntry.new("Mic/Aux", alias: "mic")]

    Obsctl::Domain::Aliases.resolve_scene(scenes, "main", ["Main Camera"]).name.should eq("Main Camera")
    Obsctl::Domain::Aliases.resolve_audio(inputs, "mic", ["Mic/Aux"]).name.should eq("Mic/Aux")
  end

  it "converts config entries into the fields resolution matches on" do
    scene = Obsctl::Config::SceneConfig.new(name: "Main Camera", alias: "main", shortcut: "1", group: "cams")
    input = Obsctl::Config::AudioInputConfig.new(name: "Mic/Aux", alias: "mic", shortcut: "m", kind: "input")

    scene.to_target_entry.should eq(Obsctl::Domain::TargetEntry.new("Main Camera", "main", "1"))
    input.to_target_entry.should eq(Obsctl::Domain::TargetEntry.new("Mic/Aux", "mic", "m"))
  end
end
