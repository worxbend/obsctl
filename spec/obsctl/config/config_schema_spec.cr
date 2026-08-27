require "../../spec_helper"

private def profile_config(
  profiles : Array(Obsctl::Config::SceneProfileConfig),
  active : String? = nil,
  scenes : Array(Obsctl::Config::SceneConfig) = [] of Obsctl::Config::SceneConfig,
)
  Obsctl::Config::Config.new(
    connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
    scenes: scenes,
    scene_profiles: profiles,
    active_scene_profile: active
  )
end

describe Obsctl::Config::ConfigSchema do
  it "round-trips hidden scene visibility metadata" do
    config = Obsctl::Config::Config.from_yaml(<<-YAML)
      version: 1
      scenes:
        - name: Utility
          hidden: true
      YAML

    config.scenes.first.hidden.should be_true
    reparsed = Obsctl::Config::Config.from_yaml(config.to_yaml)
    reparsed.scenes.first.hidden.should be_true
  end

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

  it "rejects two scene profiles whose names differ only in case or padding" do
    # Matching is case- and whitespace-insensitive, so these two would make
    # `active_scene_profile` ambiguous.
    config = profile_config([
      Obsctl::Config::SceneProfileConfig.new(name: "streaming"),
      Obsctl::Config::SceneProfileConfig.new(name: "  Streaming  "),
    ])

    error = expect_raises(Obsctl::Domain::ConfigInvalid) do
      Obsctl::Config::ConfigSchema.validate!(config)
    end
    # Reported with the name as written, so the user can find the line.
    error.message.should eq("duplicate scene profile name: '  Streaming  '")
  end

  it "rejects an unusable scene profile name, saying which rule it broke" do
    error = expect_raises(Obsctl::Domain::ConfigInvalid) do
      Obsctl::Config::ConfigSchema.validate!(profile_config([Obsctl::Config::SceneProfileConfig.new(name: "  ")]))
    end
    error.message.should eq("scene profile name must not be blank")
  end

  it "rejects an unusable hidden scene name, naming the profile it is in" do
    profile = Obsctl::Config::SceneProfileConfig.new(name: "streaming", hidden: ["bad\nname"])

    error = expect_raises(Obsctl::Domain::ConfigInvalid) do
      Obsctl::Config::ConfigSchema.validate!(profile_config([profile]))
    end
    error.message.should eq("scene profile 'streaming' hidden scene must not contain control characters")
  end

  it "warns rather than fails when the active scene profile does not exist" do
    # A hand-edited file has to degrade to "every scene visible"; refusing to
    # load would lock the user out of the dashboard over a typo.
    config = profile_config([Obsctl::Config::SceneProfileConfig.new(name: "streaming")], active: "podcast")

    Obsctl::Config::ConfigSchema.validate!(config)

    warnings = Obsctl::Config::ConfigSchema.warnings(config)
    warnings.should eq(["active scene profile 'podcast' is not defined; no scenes are hidden by a profile"])
  end

  it "warns when a profile hides a scene the config does not list" do
    config = profile_config(
      [Obsctl::Config::SceneProfileConfig.new(name: "streaming", hidden: ["Gone"])],
      scenes: [Obsctl::Config::SceneConfig.new(name: "Main")]
    )

    Obsctl::Config::ConfigSchema.warnings(config).should eq([
      "scene profile 'streaming' hides 'Gone', which is not in the scenes list",
    ])
  end

  it "stays quiet about unlisted scenes while there are no configured scenes" do
    # An empty `scenes:` is what a fresh `obsctl init` writes, so there is no
    # ground truth to check against and every profile would warn.
    config = profile_config([Obsctl::Config::SceneProfileConfig.new(name: "streaming", hidden: ["Gone"])])

    Obsctl::Config::ConfigSchema.warnings(config).should be_empty
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

  it "warns when a plaintext password is configured without exposing it" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        password_env: "",
        password: "super-secret"
      )
    )

    warnings = Obsctl::Config::ConfigSchema.warnings(config)
    warnings.size.should eq(1)
    warnings.first.should contain("connection.password")
    warnings.first.should_not contain("super-secret")
  end

  it "does not warn when only password_env is configured" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: "OBSCTL_TEST_PASSWORD")
    )

    Obsctl::Config::ConfigSchema.warnings(config).should be_empty
  end

  it "accepts a missing password environment variable for passwordless OBS" do
    env_name = "OBSCTL_SPEC_MISSING_PASSWORD"
    previous = ENV.delete(env_name)
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: env_name)
    )

    Obsctl::Config::ConfigSchema.validate!(config)
  ensure
    ENV["OBSCTL_SPEC_MISSING_PASSWORD"] = previous
  end

  it "rejects refresh intervals that would busy-loop the TUI" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
      ui: Obsctl::Config::UiConfig.new(refresh_interval_ms: 0)
    )

    expect_raises(Obsctl::Domain::ConfigInvalid, /ui.refresh_interval_ms/) do
      Obsctl::Config::ConfigSchema.validate!(config)
    end
  end

  it "warns when a configured TUI locale falls back to English" do
    config = Obsctl::Config::Config.new(ui: Obsctl::Config::UiConfig.new(locale: "fr"))

    Obsctl::Config::ConfigSchema.warnings(config).should contain(
      "ui.locale 'fr' is not supported (supported: en, uk); falling back to en"
    )
  end
end
