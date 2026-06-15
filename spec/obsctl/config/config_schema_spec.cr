require "../../spec_helper"

describe Obsctl::Config::ConfigSchema do
  it "rejects duplicate scene aliases" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
      scenes: [
        Obsctl::Config::SceneConfig.new(name: "A", alias: "main"),
        Obsctl::Config::SceneConfig.new(name: "B", alias: "main"),
      ]
    )
    expect_raises(Obsctl::Domain::ConfigInvalid) do
      Obsctl::Config::ConfigSchema.validate!(config)
    end
  end

  it "rejects invalid reconnect values" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
      reconnect: Obsctl::Config::ReconnectConfig.new(
        initial_delay_ms: 1000,
        max_delay_ms: 500
      )
    )

    error = expect_raises(Obsctl::Domain::ConfigInvalid) do
      Obsctl::Config::ConfigSchema.validate!(config)
    end
    error.message.should eq("reconnect.max_delay_ms must be greater than or equal to initial_delay_ms")
  end

  it "accepts explicit false boolean config values" do
    config = Obsctl::Config::Config.from_yaml(<<-YAML)
    version: 1
    server:
      allow_remote_shutdown: false
      start_embedded_if_missing: false
    connection:
      password_env: ""
    reconnect:
      enabled: false
    YAML

    config.server.allow_remote_shutdown.should be_false
    config.server.start_embedded_if_missing.should be_false
    config.reconnect.enabled.should be_false
  end
end
