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

  it "preserves server and reconnect settings" do
    config = Obsctl::Config::Config.new(
      server: Obsctl::Config::ServerConfig.new(
        socket_path: "/tmp/custom-obsctl.sock",
        allow_remote_shutdown: true
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(
        enabled: false,
        max_delay_ms: 1500
      )
    )

    merged = Obsctl::Config::ConfigDump.merge(config, ["Main Camera"], ["Mic/Aux"])

    merged.server.socket_path.should eq("/tmp/custom-obsctl.sock")
    merged.server.allow_remote_shutdown.should be_true
    merged.reconnect.enabled.should be_false
    merged.reconnect.max_delay_ms.should eq(1500)
  end

  it "reports duplicate aliases before writing a dumped config" do
    config = Obsctl::Config::Config.new(
      scenes: [
        Obsctl::Config::SceneConfig.new(name: "Main Camera", alias: "main"),
        Obsctl::Config::SceneConfig.new(name: "BRB", alias: "MAIN"),
      ]
    )

    expect_raises(Obsctl::Domain::ConfigInvalid, /duplicate scene alias 'main'/) do
      Obsctl::Config::ConfigDump.merge(config, ["Main Camera", "BRB"], [] of String)
    end
  end

  it "reports aliases that collide with newly discovered OBS names" do
    config = Obsctl::Config::Config.new(
      scenes: [
        Obsctl::Config::SceneConfig.new(name: "Main Camera", alias: "brb"),
      ],
      audio: Obsctl::Config::AudioConfig.new([
        Obsctl::Config::AudioInputConfig.new(name: "Mic/Aux", alias: "desktop audio"),
      ])
    )

    expect_raises(Obsctl::Domain::ConfigInvalid, /scene alias 'brb' on Main Camera matches OBS scene name BRB/) do
      Obsctl::Config::ConfigDump.merge(config, ["Main Camera", "BRB"], ["Mic/Aux", "Desktop Audio"])
    end
  end

  it "reports shortcuts that collide with newly discovered OBS input names" do
    config = Obsctl::Config::Config.new(
      audio: Obsctl::Config::AudioConfig.new([
        Obsctl::Config::AudioInputConfig.new(name: "Mic/Aux", shortcut: "alerts"),
      ])
    )

    expect_raises(Obsctl::Domain::ConfigInvalid, /audio input shortcut 'alerts' on Mic\/Aux matches OBS audio input name Alerts/) do
      Obsctl::Config::ConfigDump.merge(config, [] of String, ["Mic/Aux", "Alerts"])
    end
  end
end
