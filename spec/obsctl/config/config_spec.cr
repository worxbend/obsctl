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

  it "loads and rewrites the keymap section a Rust-written config carries" do
    yaml = <<-YAML
      version: 1
      keymap:
        quit: ["Q"]
        command_palette: [":"]
      YAML

    config = Obsctl::Config::Config.from_yaml(yaml)
    config.keymap.quit.should eq(["Q"])
    config.keymap.command_palette.should eq([":"])
    # Sections the file left out keep their defaults rather than emptying.
    config.keymap.reload_config.should eq(["r"])
    config.keymap.dump_config.should eq(["D"])

    # A rewrite has to carry the section back out, or `config migrate` would
    # drop bindings the user wrote.
    rewritten = Obsctl::Config::Config.from_yaml(config.to_yaml)
    rewritten.keymap.quit.should eq(["Q"])
    rewritten.keymap.command_palette.should eq([":"])
  end

  it "loads and rewrites obsctl scene profiles" do
    # Top-level, beside the `scenes:` list these describe, and spelled the way
    # obsctl-rs spells them so one config file serves both implementations.
    yaml = <<-YAML
      version: 1
      scene_profiles:
        - name: streaming
          hidden:
            - Utility Cam
            - BRB Loop
        - name: editing
          hidden: []
      active_scene_profile: streaming
      YAML

    config = Obsctl::Config::Config.from_yaml(yaml)
    config.active_scene_profile.should eq("streaming")
    config.scene_profiles.map(&.name).should eq(["streaming", "editing"])
    config.scene_profiles.first.hidden.should eq(["Utility Cam", "BRB Loop"])
    # An empty list is a profile that hides nothing, not an absent setting.
    config.scene_profiles.last.hidden.should be_empty

    # A rewrite has to carry the keys back out, or `config migrate` would drop
    # profiles the dashboard saved.
    rewritten = Obsctl::Config::Config.from_yaml(config.to_yaml)
    rewritten.scene_profiles.should eq(config.scene_profiles)
    rewritten.active_scene_profile.should eq("streaming")
  end

  it "matches the active profile trimmed and case-insensitively" do
    yaml = <<-YAML
      version: 1
      scene_profiles:
        - name: Streaming
          hidden: [Utility Cam]
      active_scene_profile: "  streaming  "
      YAML

    # The stored spelling comes back, not the one that was written in
    # `active_scene_profile`: the profile entry is the record of its name.
    Obsctl::Config::Config.from_yaml(yaml).active_scene_profile_config.try(&.name).should eq("Streaming")
  end

  it "resolves an active profile as a replacement for the per-scene flags" do
    yaml = <<-YAML
      version: 1
      scenes:
        - name: Main
        - name: Utility Cam
          hidden: true
        - name: Cam
      scene_profiles:
        - name: streaming
          hidden: [Cam]
      active_scene_profile: streaming
      YAML

    visibility = Obsctl::Config::Config.from_yaml(yaml).scene_visibility

    # The profile is the whole answer: `Cam` goes because it names it, and
    # `Utility Cam` comes back even though `scenes:` marks it hidden.
    visibility.hidden?("Cam").should be_true
    visibility.hidden?("Utility Cam").should be_false
  end

  it "writes no scene profile section when none is configured" do
    # Existing config files predate the feature, so a rewrite of one must come
    # back byte-identical rather than gaining an empty section.
    Obsctl::Config::Config.default.to_yaml.should_not contain("scene_profiles")
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

  it "round-trips TUI appearance and partial custom theme settings" do
    config = Obsctl::Config::Config.from_yaml(<<-YAML)
      version: 1
      connection:
        password_env: ""
      ui:
        refresh_interval_ms: 333
        command_palette_prefix: ":"
        advanced_ui: false
        show_icons: false
        theme: custom
        locale: uk
        custom_theme:
          bg: "#010203"
          accent: "aabbcc"
      YAML

    config.ui.refresh_interval_ms.should eq(333)
    config.ui.command_palette_prefix.should eq(":")
    config.ui.advanced_ui.should be_false
    config.ui.show_icons.should be_false
    config.ui.custom_theme.try(&.bg).should eq("#010203")

    reparsed = Obsctl::Config::Config.from_yaml(config.to_yaml)
    reparsed.ui.should eq(config.ui)
  end

  # `CommandExecutor` edits a copy and only adopts it once the write to disk
  # succeeded. That promise is worth nothing if the copy shares its collections
  # with the live object, so every collection is pinned here rather than only
  # the ones today's handlers happen to touch.
  it "detaches every mutable collection when copying a config" do
    config = Obsctl::Config::Config.new(
      scenes: [Obsctl::Config::SceneConfig.new(name: "Main")],
      scene_profiles: [Obsctl::Config::SceneProfileConfig.new(name: "streaming")],
      audio: Obsctl::Config::AudioConfig.new(
        inputs: [Obsctl::Config::AudioInputConfig.new(name: "Mic/Aux")]
      ),
    )

    copy = config.copy
    copy.scenes << Obsctl::Config::SceneConfig.new(name: "Cam 2")
    copy.scene_profiles << Obsctl::Config::SceneProfileConfig.new(name: "recording")
    copy.audio.inputs << Obsctl::Config::AudioInputConfig.new(name: "Desktop Audio")
    copy.keymap.quit << "ctrl+d"

    config.scenes.map(&.name).should eq(["Main"])
    config.scene_profiles.map(&.name).should eq(["streaming"])
    config.audio.inputs.map(&.name).should eq(["Mic/Aux"])
    config.keymap.quit.should eq(["q", "ctrl+c"])
  end

  it "carries every setting across a copy" do
    original = Obsctl::Config::Config.from_yaml(<<-YAML)
      version: 1
      server:
        pid_file: "/run/obsctl.pid"
      connection:
        host: "10.0.0.2"
        password_env: ""
      reconnect:
        initial_delay_ms: 900
      scenes:
        - name: "Main"
          hidden: true
      scene_profiles:
        - name: "streaming"
          hidden: ["Main"]
      active_scene_profile: "streaming"
      audio:
        inputs:
          - name: "Mic/Aux"
            alias: "mic"
      ui:
        theme: "custom"
      keymap:
        quit: ["Q"]
      YAML

    original.copy.to_yaml.should eq(original.to_yaml)
  end
end
