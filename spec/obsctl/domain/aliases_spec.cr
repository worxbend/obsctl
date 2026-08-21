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

  it "resolves unconfigured live OBS scene and audio names" do
    config = Obsctl::Config::Config.new

    Obsctl::Domain::Aliases.resolve_scene(config, "Scene 2", ["Scene 1", "Scene 2"]).name.should eq("Scene 2")
    Obsctl::Domain::Aliases.resolve_audio(config, "desktop audio", ["Desktop Audio"]).name.should eq("Desktop Audio")
  end

  it "preserves configured aliases when live names are merged" do
    config = Obsctl::Config::Config.new(
      scenes: [Obsctl::Config::SceneConfig.new("Main Camera", alias: "main")],
      audio: Obsctl::Config::AudioConfig.new([
        Obsctl::Config::AudioInputConfig.new("Mic/Aux", alias: "mic"),
      ])
    )

    Obsctl::Domain::Aliases.resolve_scene(config, "main", ["Main Camera"]).name.should eq("Main Camera")
    Obsctl::Domain::Aliases.resolve_audio(config, "mic", ["Mic/Aux"]).name.should eq("Mic/Aux")
  end
end

describe Obsctl::Domain::Aliases do
  describe ".volume_mul_to_percent" do
    it "converts an obs-websocket multiplier to the user-facing scale" do
      Obsctl::Domain::Aliases.volume_mul_to_percent(0.0).should eq(0)
      Obsctl::Domain::Aliases.volume_mul_to_percent(0.5).should eq(50)
      Obsctl::Domain::Aliases.volume_mul_to_percent(1.0).should eq(100)
    end

    # OBS allows gain above unity, which has no spelling on a 0-100 scale.
    it "clamps a multiplier above unity to 100" do
      Obsctl::Domain::Aliases.volume_mul_to_percent(2.5).should eq(100)
    end

    it "round-trips with volume_percent_to_mul" do
      (0..100).each do |percent|
        mul = Obsctl::Domain::Aliases.volume_percent_to_mul(percent)
        Obsctl::Domain::Aliases.volume_mul_to_percent(mul).should eq(percent)
      end
    end
  end
end
