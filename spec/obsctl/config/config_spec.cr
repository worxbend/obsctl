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
