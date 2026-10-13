require "../../spec_helper"

describe "shared obsctl config" do
  it "preserves every setting in the shared Rust/Crystal fixture" do
    path = File.expand_path("../../fixtures/config/shared.yml", __DIR__)
    config = Obsctl::Config::Config.from_yaml(File.read(path))
    Obsctl::Config::ConfigSchema.validate!(config)
    config.ui.mouse.should be_false
    config.server.start_embedded_if_missing.should be_false
    config.audio.inputs.first.kind.should eq("wasapi_input_capture")

    rewritten = Obsctl::Config::Config.from_yaml(config.to_yaml)
    rewritten.to_yaml.should eq(config.to_yaml)
    rewritten.ui.mouse.should be_false
    rewritten.server.pid_file.should eq("/tmp/obsctl.pid")
    rewritten.audio.inputs.first.kind.should eq("wasapi_input_capture")
    rewritten.keymap.quit.should eq(["Q", "ctrl+c"])
  end

  it "lets an empty canonical reconnect section override legacy settings" do
    config = Obsctl::Config::Config.from_yaml(<<-YAML)
      connection:
        reconnect:
          enabled: false
          initial_delay_ms: 25
      reconnect: {}
      YAML
    config.reconnect.enabled.should be_true
    config.reconnect.initial_delay_ms.should eq(500)
  end

  it "defaults mouse capture on when older configs omit the setting" do
    Obsctl::Config::Config.from_yaml("version: 1\n").ui.mouse.should be_true
  end
end
