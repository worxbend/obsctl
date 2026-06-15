require "../../spec_helper"
require "../../../src/obsctl/tui/session"

private class FakeSessionClient < Obsctl::TUI::SessionClient
  getter set_scenes = [] of String
  getter mutes = [] of NamedTuple(name: String, muted: Bool)
  getter toggles = [] of String
  getter volumes = [] of NamedTuple(name: String, percent: Int32)
  getter closed = false

  def initialize(@snapshots : Array(Obsctl::OBS::State::ObsSnapshot), @scene_names : Array(String), @input_names : Array(String))
    @connected = false
  end

  def connect : Nil
    @connected = true
  end

  def close : Nil
    @closed = true
  end

  def snapshot : Obsctl::OBS::State::ObsSnapshot
    @snapshots.shift
  end

  def set_scene(name : String) : Nil
    @set_scenes << name
  end

  def mute(name : String, muted : Bool) : Nil
    @mutes << {name: name, muted: muted}
  end

  def toggle_mute(name : String) : Nil
    @toggles << name
  end

  def set_volume(name : String, percent : Int32) : Nil
    @volumes << {name: name, percent: percent}
  end

  def scene_names : Array(String)
    @scene_names
  end

  def input_names : Array(String)
    @input_names
  end
end

private def tui_config(scene_alias = "main", audio_alias = "mic")
  ENV["OBSCTL_TUI_TEST_PASSWORD"] = "secret"
  Obsctl::Config::Config.new(
    connection: Obsctl::Config::ConnectionConfig.new(password_env: "OBSCTL_TUI_TEST_PASSWORD"),
    scenes: [
      Obsctl::Config::SceneConfig.new(name: "Main Camera", alias: scene_alias, shortcut: "1"),
      Obsctl::Config::SceneConfig.new(name: "BRB", alias: "brb", shortcut: "2"),
    ],
    audio: Obsctl::Config::AudioConfig.new([
      Obsctl::Config::AudioInputConfig.new(name: "Mic/Aux", alias: audio_alias, shortcut: "m"),
    ])
  )
end

private def snapshot(current_scene : String, muted = false, volume = 70)
  Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: current_scene,
    scenes: [
      Obsctl::OBS::State::SceneState.new(name: "Main Camera", alias: "main", shortcut: "1", active: current_scene == "Main Camera"),
      Obsctl::OBS::State::SceneState.new(name: "BRB", alias: "brb", shortcut: "2", active: current_scene == "BRB"),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new(name: "Mic/Aux", alias: "mic", shortcut: "m", muted: muted, volume_percent: volume),
    ]
  )
end

private def new_session(config, path, client)
  Obsctl::TUI::Session.new(config, path, ->(_config : Obsctl::Config::Config) {
    client.as(Obsctl::TUI::SessionClient)
  })
end

describe Obsctl::TUI::Session do
  it "refreshes the displayed snapshot after a scene command succeeds" do
    client = FakeSessionClient.new(
      [snapshot("Main Camera"), snapshot("BRB")],
      ["Main Camera", "BRB"],
      ["Mic/Aux"]
    )
    session = new_session(tui_config, "/tmp/obsctl-tui-session.yml", client)

    session.start
    result = session.execute_line("/scene 2")

    client.set_scenes.should eq(["BRB"])
    result.model.last_result.should eq("scene set: BRB")
    result.model.snapshot.try(&.current_scene).should eq("BRB")
  end

  it "refreshes audio state after mute and volume commands succeed" do
    client = FakeSessionClient.new(
      [snapshot("Main Camera", false, 70), snapshot("Main Camera", true, 70), snapshot("Main Camera", true, 25)],
      ["Main Camera", "BRB"],
      ["Mic/Aux"]
    )
    session = new_session(tui_config, "/tmp/obsctl-tui-session.yml", client)

    session.start
    muted = session.execute_line("/mute mic")
    volume = session.execute_line("/vol m 25")

    client.mutes.should eq([{name: "Mic/Aux", muted: true}])
    client.volumes.should eq([{name: "Mic/Aux", percent: 25}])
    muted.model.snapshot.try(&.audio_inputs.first.muted).should eq(true)
    volume.model.snapshot.try(&.audio_inputs.first.volume_percent).should eq(25)
  end

  it "reloads config from the configured path" do
    path = File.tempname("obsctl-tui-reload", ".yml")
    begin
      Obsctl::Config::ConfigWriter.new.write(path, tui_config("primary", "voice"), backup: false)
      client = FakeSessionClient.new(
        [snapshot("Main Camera"), snapshot("Main Camera")],
        ["Main Camera", "BRB"],
        ["Mic/Aux"]
      )
      session = new_session(tui_config, path, client)

      session.start
      result = session.execute_line("/reload-config")

      result.model.last_result.should eq("config reloaded: #{path}")
      session.config.scenes.first.alias.should eq("primary")
      session.config.audio.inputs.first.alias.should eq("voice")
    ensure
      File.delete(path) if path && File.exists?(path)
    end
  end

  it "dumps config through the active client and keeps the display refreshed" do
    path = File.tempname("obsctl-tui-dump", ".yml")
    begin
      Obsctl::Config::ConfigWriter.new.write(path, tui_config, backup: false)
      client = FakeSessionClient.new(
        [snapshot("Main Camera"), snapshot("Main Camera")],
        ["Main Camera", "BRB", "Screen Share"],
        ["Mic/Aux", "Desktop Audio"]
      )
      session = new_session(tui_config, path, client)

      session.start
      result = session.execute_line("/dump-config")
      written = Obsctl::Config::ConfigLoader.new.load(path)

      result.model.last_result.should eq("config dumped: #{path}")
      result.model.snapshot.try(&.connected).should eq(true)
      written.scenes.map(&.name).should contain("Screen Share")
      written.audio.inputs.map(&.name).should contain("Desktop Audio")
      written.scenes.find { |scene| scene.name == "Main Camera" }.try(&.alias).should eq("main")
    ensure
      File.delete(path) if path && File.exists?(path)
      Dir.glob("#{path}.bak.*").each { |backup| File.delete(backup) }
    end
  end
end
