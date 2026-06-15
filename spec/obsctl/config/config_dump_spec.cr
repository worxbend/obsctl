require "../../spec_helper"

describe Obsctl::Config::ConfigDump do
  it "preserves aliases and adds missing OBS objects" do
    config = Obsctl::Config::Config.new(
      scenes: [Obsctl::Config::SceneConfig.new(name: "Main Camera", alias: "main")]
    )
    merged = Obsctl::Config::ConfigDump.merge(config, ["Main Camera", "BRB"], ["Mic/Aux"])
    merged.scenes.find { |scene| scene.name == "Main Camera" }.try(&.alias).should eq("main")
    merged.scenes.find { |scene| scene.name == "BRB" }.should_not be_nil
    merged.audio.inputs.find { |input| input.name == "Mic/Aux" }.should_not be_nil
  end
end
