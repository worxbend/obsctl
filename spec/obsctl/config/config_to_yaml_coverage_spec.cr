require "../../spec_helper"
require "../../../src/obsctl/config/config"

# `Config#to_yaml` is hand-written, so it is the one place in the config layer
# that does not follow from the `config_value` declarations. Adding a setting is
# a single line in `config.cr`, and everything else — the getter, the YAML
# mapping that reads it, the initializer — comes from that line. The writer does
# not: a new field loads fine and is then silently dropped the next time the
# file is written, which is how a user loses a setting to `obsctl config
# migrate` without an error anywhere.
#
# These examples close that gap mechanically. Each one takes the field names the
# macro recorded in `FIELD_NAMES` and asserts the writer emitted every one of
# them. The config under test sets every optional field and flips every boolean
# away from its default, because the writers legitimately omit nil optionals and
# off flags — leaving any of them unset would let a missing key look like a
# deliberate omission.
private def canonical_yaml : YAML::Any
  config = Obsctl::Config::Config.new(
    version: 1,
    server: Obsctl::Config::ServerConfig.new(
      socket_path: "/tmp/obsctl.sock",
      pid_file: "/tmp/obsctl.pid",
      allow_remote_shutdown: true,
      start_embedded_if_missing: false,
    ),
    connection: Obsctl::Config::ConnectionConfig.new(
      host: "192.0.2.10",
      port: 4456,
      password_env: "OBS_PASSWORD",
      password: "secret",
      connect_timeout_ms: 1234,
      request_timeout_ms: 4321,
    ),
    reconnect: Obsctl::Config::ReconnectConfig.new(
      enabled: false,
      endless: false,
      initial_delay_ms: 100,
      max_delay_ms: 200,
      multiplier: 2.0,
      jitter_ms: 10,
    ),
    scenes: [
      Obsctl::Config::SceneConfig.new(
        name: "Main Camera",
        alias: "main",
        shortcut: "1",
        group: "live",
        stale: true,
        hidden: true,
      ),
    ],
    audio: Obsctl::Config::AudioConfig.new(
      inputs: [
        Obsctl::Config::AudioInputConfig.new(
          name: "Mic/Aux",
          alias: "mic",
          shortcut: "m",
          kind: "input",
          stale: true,
        ),
      ]
    ),
    ui: Obsctl::Config::UiConfig.new(
      refresh_interval_ms: 500,
      command_palette_prefix: ":",
      advanced_ui: false,
      show_icons: false,
      theme: "nord",
      custom_theme: Obsctl::Config::CustomThemeConfig.new(
        bg: "#000000",
        accent: "#111111",
        accent_alt: "#222222",
        fg: "#333333",
        muted: "#444444",
        border: "#555555",
        border_focus: "#666666",
        success: "#777777",
        warning: "#888888",
        danger: "#999999",
        info: "#aaaaaa",
        highlight_bg: "#bbbbbb",
        highlight_fg: "#cccccc",
      ),
      locale: "uk",
    ),
    keymap: Obsctl::Config::KeymapConfig.new(
      quit: ["q"],
      command_palette: ["/"],
      reload_config: ["r"],
      dump_config: ["D"],
    ),
  )

  YAML.parse(config.to_yaml)
end

# Asserts the mapping at `path` carries a key for every declared field.
private def assert_writes_every_field(
  path : Array(String),
  declared : Array(String),
  skip : Array(String) = [] of String,
) : Nil
  node = canonical_yaml
  # A numeric step indexes a sequence: `scenes` and `audio.inputs` are lists,
  # and one entry is enough to see which of its fields the writer emits.
  path.each { |step| node = (index = step.to_i?) ? node[index] : node[step] }
  written = node.as_h.keys.map(&.as_s)

  (declared - skip).each do |field|
    fail "#{path.join('.')}.#{field} is declared but `Config#to_yaml` never writes it" unless written.includes?(field)
  end
end

describe Obsctl::Config::Config do
  describe "#to_yaml" do
    it "writes every declared server field" do
      assert_writes_every_field(["server"], Obsctl::Config::ServerConfig::FIELD_NAMES)
    end

    it "writes every declared connection field" do
      # `reconnect` is the legacy nested policy. `Config.from_yaml` promotes it
      # to the top-level `reconnect` section and the writer deliberately never
      # emits it again, which is what converges an old file onto the current
      # schema. Writing it back would recreate the duplicate this migration
      # exists to remove.
      assert_writes_every_field(
        ["connection"],
        Obsctl::Config::ConnectionConfig::FIELD_NAMES,
        skip: ["reconnect"]
      )
    end

    it "writes every declared reconnect field" do
      assert_writes_every_field(["reconnect"], Obsctl::Config::ReconnectConfig::FIELD_NAMES)
    end

    it "writes every declared scene field" do
      assert_writes_every_field(["scenes", "0"], Obsctl::Config::SceneConfig::FIELD_NAMES)
    end

    it "writes every declared audio input field" do
      assert_writes_every_field(["audio", "inputs", "0"], Obsctl::Config::AudioInputConfig::FIELD_NAMES)
    end

    it "writes every declared ui field" do
      assert_writes_every_field(["ui"], Obsctl::Config::UiConfig::FIELD_NAMES)
    end

    it "writes every declared custom theme field" do
      assert_writes_every_field(["ui", "custom_theme"], Obsctl::Config::CustomThemeConfig::FIELD_NAMES)
    end

    it "writes every declared keymap field" do
      assert_writes_every_field(["keymap"], Obsctl::Config::KeymapConfig::FIELD_NAMES)
    end
  end
end
