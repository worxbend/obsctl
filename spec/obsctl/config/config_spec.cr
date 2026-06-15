require "../../spec_helper"

describe Obsctl::Config::Config do
  it "loads and writes known config fields" do
    yaml = <<-YAML
    version: 1
    connection:
      host: "127.0.0.1"
      port: 4455
      password_env: ""
    scenes:
      - name: "Main Camera"
        alias: "main"
        shortcut: "1"
    audio:
      inputs:
        - name: "Mic/Aux"
          alias: "mic"
          shortcut: "m"
          kind: "input"
    YAML

    config = Obsctl::Config::Config.from_yaml(yaml)
    config.scenes.first.alias.should eq("main")
    config.to_yaml.should contain("Main Camera")
  end

  it "rejects unknown top-level fields instead of silently dropping them" do
    yaml = <<-YAML
    version: 1
    future_field:
      enabled: true
    YAML

    error = expect_raises(Obsctl::Domain::ConfigInvalid) do
      Obsctl::Config::Config.from_yaml(yaml)
    end
    error.message.should eq("unsupported top-level config field: future_field")
  end

  it "preserves an intentionally blank password_env as no env password" do
    config = Obsctl::Config::Config.from_yaml(<<-YAML)
    version: 1
    connection:
      host: 127.0.0.1
      port: 4455
      password_env:
    YAML

    config.connection.password_env.should eq("")
  end

  it "loads and writes server and top-level reconnect settings" do
    config = Obsctl::Config::Config.from_yaml(<<-YAML)
    version: 1
    server:
      socket_path: /tmp/obsctl-custom.sock
      pid_file: /tmp/obsctl.pid
      allow_remote_shutdown: true
      start_embedded_if_missing: false
    connection:
      host: 127.0.0.1
      port: 4455
      password_env: ""
    reconnect:
      enabled: false
      endless: false
      initial_delay_ms: 100
      max_delay_ms: 2000
      multiplier: 2.0
      jitter_ms: 0
    YAML

    config.server.socket_path.should eq("/tmp/obsctl-custom.sock")
    config.server.pid_file.should eq("/tmp/obsctl.pid")
    config.server.allow_remote_shutdown.should be_true
    config.server.start_embedded_if_missing.should be_false
    config.reconnect.enabled.should be_false
    config.reconnect.endless.should be_false
    config.reconnect.initial_delay_ms.should eq(100)
    config.reconnect.max_delay_ms.should eq(2000)
    config.reconnect.multiplier.should eq(2.0)
    config.reconnect.jitter_ms.should eq(0)

    written = config.to_yaml
    written.should contain("server:")
    written.should contain("reconnect:")
    written.should_not contain("  reconnect:\n    enabled")
  end

  it "loads legacy connection.reconnect settings for compatibility" do
    config = Obsctl::Config::Config.from_yaml(<<-YAML)
    version: 1
    connection:
      host: 127.0.0.1
      port: 4455
      password_env: ""
      reconnect:
        enabled: false
        initial_delay_ms: 25
        max_delay_ms: 50
        multiplier: 1.0
    YAML

    config.reconnect.enabled.should be_false
    config.reconnect.initial_delay_ms.should eq(25)
    config.reconnect.max_delay_ms.should eq(50)
    config.reconnect.multiplier.should eq(1.0)
  end

  it "prefers top-level reconnect over legacy connection.reconnect" do
    config = Obsctl::Config::Config.from_yaml(<<-YAML)
    version: 1
    connection:
      password_env: ""
      reconnect:
        enabled: false
        initial_delay_ms: 25
    reconnect:
      enabled: true
      initial_delay_ms: 75
    YAML

    config.reconnect.enabled.should be_true
    config.reconnect.initial_delay_ms.should eq(75)
  end

  it "loads numeric YAML shortcuts as strings" do
    config = Obsctl::Config::Config.from_yaml(<<-YAML)
    version: 1
    scenes:
      - name: Screen Share
        shortcut: 2
    audio:
      inputs:
        - name: Mic/Aux
          shortcut: 3
    YAML

    config.scenes.first.shortcut.should eq("2")
    config.audio.inputs.first.shortcut.should eq("3")
  end
end
