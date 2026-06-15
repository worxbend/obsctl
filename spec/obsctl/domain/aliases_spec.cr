require "../../spec_helper"

describe Obsctl::Domain::Aliases do
  it "resolves scene lookup by shortcut first" do
    config = Obsctl::Config::Config.new(
      scenes: [
        Obsctl::Config::SceneConfig.new(name: "Main Camera", alias: "main", shortcut: "1"),
      ]
    )
    Obsctl::Domain::Aliases.resolve_scene(config, "1").name.should eq("Main Camera")
  end

  it "converts volume percent linearly" do
    Obsctl::Domain::Aliases.volume_percent_to_mul(70).should eq(0.7)
  end
end
