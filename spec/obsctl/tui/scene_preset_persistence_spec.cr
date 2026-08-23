require "../../spec_helper"
require "../../../src/obsctl/tui/scene_preset_persistence"

private def presets_config(
  active : String?,
  presets : Array(Obsctl::Config::ScenePresetConfig),
) : Obsctl::Config::ScenePresetsConfig
  Obsctl::Config::ScenePresetsConfig.new(active: active, presets: presets)
end

describe Obsctl::TUI::ScenePresetPersistence do
  it "persists every preset while preserving every other ui field" do
    path = File.join(Dir.tempdir, "obsctl-scene-presets-#{Random.rand(1_000_000)}.yml")
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
      ui: Obsctl::Config::UiConfig.new(
        refresh_interval_ms: 333,
        command_palette_prefix: ":",
        advanced_ui: false,
        show_icons: false,
        theme: "ember",
        locale: "uk"
      )
    )
    Obsctl::Config::ConfigWriter.new.write(path, config, backup: false)

    presets = Obsctl::TUI::ScenePresets.new(
      [
        Obsctl::TUI::ScenePreset.new("streaming", Set{"Utility Cam", "BRB Loop"}),
        Obsctl::TUI::ScenePreset.new("editing", Set(String).new),
      ],
      "streaming"
    )

    Obsctl::TUI::ScenePresetPersistence.save(path, presets)
      .should eq("scene preset saved: streaming")

    persisted = Obsctl::Config::Config.from_yaml(File.read(path))
    persisted.ui.scene_presets.active.should eq("streaming")
    persisted.ui.scene_presets.presets.map(&.name).should eq(["streaming", "editing"])
    # Sorted, not in the order the set happened to iterate, so a second save of
    # the same preset produces a byte-identical file.
    persisted.ui.scene_presets.presets[0].hidden_scenes.should eq(["BRB Loop", "Utility Cam"])
    persisted.ui.scene_presets.presets[1].hidden_scenes.should be_empty

    persisted.ui.theme.should eq("ember")
    persisted.ui.refresh_interval_ms.should eq(333)
    persisted.ui.command_palette_prefix.should eq(":")
    persisted.ui.advanced_ui.should be_false
    persisted.ui.show_icons.should be_false
    persisted.ui.locale.should eq("uk")
  ensure
    File.delete(path) if path && File.exists?(path)
    Dir.glob("#{path}.bak.*").each { |backup| File.delete(backup) } if path
  end

  it "reports no persistence target without treating the edit as failure" do
    presets = Obsctl::TUI::ScenePresets.new(
      [Obsctl::TUI::ScenePreset.new("streaming", Set{"Utility Cam"})],
      "streaming"
    )

    Obsctl::TUI::ScenePresetPersistence.save(nil, presets)
      .should eq("scene preset applied (no config file to persist to)")
  end

  it "reads configured presets and the active one out of a config" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
      ui: Obsctl::Config::UiConfig.new(
        scene_presets: presets_config(
          "editing",
          [
            Obsctl::Config::ScenePresetConfig.new(name: "streaming", hidden_scenes: ["Utility Cam"]),
            Obsctl::Config::ScenePresetConfig.new(name: "editing", hidden_scenes: ["Intro", "Outro"]),
          ]
        )
      )
    )

    presets = Obsctl::TUI::ScenePresetPersistence.from_config(config)
    presets.active.should eq("editing")
    presets.presets.map(&.name).should eq(["streaming", "editing"])
    presets.active_preset.not_nil!.hidden_scenes.should eq(Set{"Intro", "Outro"})
    presets.hidden_names.should eq(Set{"Intro", "Outro"})
  end

  it "reads a config that never used presets as an empty set with nothing active" do
    presets = Obsctl::TUI::ScenePresetPersistence.from_config(Obsctl::Config::Config.default)
    presets.presets.should be_empty
    presets.active.should be_nil
    presets.active_preset.should be_nil
    presets.hidden_names.should be_empty
  end

  it "hides nothing when the active name matches no configured preset" do
    # A hand-edited file naming a preset that was deleted has to degrade to
    # "every scene visible"; the alternative is an empty scene list the user
    # cannot escape from inside the dashboard.
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
      ui: Obsctl::Config::UiConfig.new(
        scene_presets: presets_config(
          "gone",
          [Obsctl::Config::ScenePresetConfig.new(name: "streaming", hidden_scenes: ["Utility Cam"])]
        )
      )
    )

    presets = Obsctl::TUI::ScenePresetPersistence.from_config(config)
    presets.active.should eq("gone")
    presets.active_preset.should be_nil
    presets.hidden_names.should be_empty
  end

  it "replaces a preset of the same name instead of appending a duplicate" do
    presets = Obsctl::TUI::ScenePresets.empty
      .upsert("streaming", Set{"Utility Cam"})
      .upsert("editing", Set(String).new)
      .upsert("streaming", Set{"BRB Loop"})

    presets.presets.map(&.name).should eq(["streaming", "editing"])
    presets.presets[0].hidden_scenes.should eq(Set{"BRB Loop"})
    presets.index_of("editing").should eq(1)
    presets.index_of("missing").should be_nil
  end

  it "keeps the preset list when the active preset changes" do
    presets = Obsctl::TUI::ScenePresets.empty
      .upsert("streaming", Set{"Utility Cam"})
      .activate("streaming")

    presets.hidden_names.should eq(Set{"Utility Cam"})
    presets.activate(nil).hidden_names.should be_empty
    presets.activate(nil).presets.map(&.name).should eq(["streaming"])
  end
end
