require "../../spec_helper"
require "../../../src/obsctl/config/config_writer"
require "../../../src/obsctl/tui/session"

private class FakeSessionClient < Obsctl::TUI::SessionClient
  getter set_scenes = [] of String
  getter mutes = [] of NamedTuple(name: String, muted: Bool)
  getter toggles = [] of String
  getter volumes = [] of NamedTuple(name: String, percent: Int32)
  getter closed = false

  def initialize(
    @snapshots : Array(Obsctl::OBS::State::ObsSnapshot),
    @scene_names : Array(String),
    @input_names : Array(String),
    @events : Array(Obsctl::OBS::Protocol::Event) = [] of Obsctl::OBS::Protocol::Event,
  )
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

  def set_scene(target : String) : Nil
    @set_scenes << target
  end

  def mute(target : String, muted : Bool) : Nil
    @mutes << {name: target, muted: muted}
  end

  def toggle_mute(target : String) : Nil
    @toggles << target
  end

  def set_volume(target : String, percent : Int32) : Nil
    @volumes << {name: target, percent: percent}
  end

  def scene_names : Array(String)
    @scene_names
  end

  def input_names : Array(String)
    @input_names
  end

  def next_event : Obsctl::OBS::Protocol::Event?
    @events.shift?
  end

  def next_snapshot : Obsctl::OBS::State::ObsSnapshot?
    nil
  end

  def dump_config : Nil
  end

  def reload_config : Nil
  end
end

private class FailingSessionClient < Obsctl::TUI::SessionClient
  def connect : Nil
    raise Obsctl::Domain::ConnectionFailed.new("temporary connection failure")
  end

  def close : Nil
  end

  def snapshot : Obsctl::OBS::State::ObsSnapshot
    raise Obsctl::Domain::ConnectionFailed.new("not connected")
  end

  def set_scene(target : String) : Nil
  end

  def mute(target : String, muted : Bool) : Nil
  end

  def toggle_mute(target : String) : Nil
  end

  def set_volume(target : String, percent : Int32) : Nil
  end

  def scene_names : Array(String)
    [] of String
  end

  def input_names : Array(String)
    [] of String
  end

  def next_event : Obsctl::OBS::Protocol::Event?
    nil
  end

  def next_snapshot : Obsctl::OBS::State::ObsSnapshot?
    nil
  end

  def dump_config : Nil
  end

  def reload_config : Nil
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

private def reconnecting_tui_config
  config = tui_config
  Obsctl::Config::Config.new(
    connection: Obsctl::Config::ConnectionConfig.new(
      password_env: "OBSCTL_TUI_TEST_PASSWORD",
      reconnect: Obsctl::Config::ReconnectConfig.new(
        enabled: true,
        initial_delay_ms: 0,
        max_delay_ms: 0,
        multiplier: 1.0
      )
    ),
    ui: config.ui,
    scenes: config.scenes,
    audio: config.audio,
    keymap: config.keymap
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

private def event(type : String, data)
  Obsctl::OBS::Protocol::Event.new(type, JSON.parse(data.to_json))
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

    client.set_scenes.should eq(["2"])
    result.model.last_result.should eq("scene set: 2")
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

    client.mutes.should eq([{name: "mic", muted: true}])
    client.volumes.should eq([{name: "m", percent: 25}])
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

      result.model.last_result.should eq("config dumped: #{path}")
      result.model.snapshot.try(&.connected).should eq(true)
    ensure
      File.delete(path) if path && File.exists?(path)
      Dir.glob("#{path}.bak.*").each { |backup| File.delete(backup) }
    end
  end

  it "updates the model from queued scene and audio events" do
    client = FakeSessionClient.new(
      [snapshot("Main Camera", false, 70)],
      ["Main Camera", "BRB"],
      ["Mic/Aux"],
      [
        event("CurrentProgramSceneChanged", {"sceneName" => "BRB"}),
        event("InputMuteStateChanged", {"inputName" => "Mic/Aux", "inputMuted" => true}),
        event("InputVolumeChanged", {"inputName" => "Mic/Aux", "inputVolumeMul" => 0.25, "inputVolumeDb" => -12.0}),
      ]
    )
    session = new_session(tui_config, "/tmp/obsctl-tui-session.yml", client)

    session.start
    model = session.poll_events

    model.last_result.should eq("state updated")
    model.snapshot.try(&.current_scene).should eq("BRB")
    model.snapshot.try(&.scenes.find { |scene| scene.name == "BRB" }.try(&.active)).should eq(true)
    model.snapshot.try(&.audio_inputs.first.muted).should eq(true)
    model.snapshot.try(&.audio_inputs.first.volume_percent).should eq(25)
  end

  it "reconnects on poll when the configured reconnect delay has elapsed" do
    clients = [
      FailingSessionClient.new.as(Obsctl::TUI::SessionClient),
      FakeSessionClient.new([snapshot("Main Camera")], ["Main Camera", "BRB"], ["Mic/Aux"]).as(Obsctl::TUI::SessionClient),
    ]
    session = Obsctl::TUI::Session.new(reconnecting_tui_config, "/tmp/obsctl-tui-session.yml", ->(_config : Obsctl::Config::Config) {
      clients.shift
    })

    disconnected = session.start
    reconnected = session.poll_events

    disconnected.snapshot.try(&.connected).should eq(false)
    disconnected.last_result.should eq("temporary connection failure")
    reconnected.last_result.should eq("reconnected")
    reconnected.snapshot.try(&.connected).should eq(true)
  end
end
