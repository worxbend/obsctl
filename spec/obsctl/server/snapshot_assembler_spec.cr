require "../../spec_helper"
# `SnapshotAssembler` names `OBS::Client` in `compose` without requiring it --
# that require is the daemon's marker for owning a connection, and the boundary
# spec allows it only in the supervisor -- so the type is brought in here.
require "../../../src/obsctl/obs/client"
require "../../../src/obsctl/server/snapshot_assembler"

# The scene, audio and scene-profile merge used to live inside `OBS::Client`,
# where the only way to reach it was to stand up a websocket and connect to it.
# It is obsctl's own policy, so every example below runs on a plain `Config`
# with no server, no socket and no client.
private def assembler_config(
  scenes = [] of Obsctl::Config::SceneConfig,
  inputs = [] of Obsctl::Config::AudioInputConfig,
  scene_profiles = [] of Obsctl::Config::SceneProfileConfig,
  active_scene_profile : String? = nil,
) : Obsctl::Config::Config
  Obsctl::Config::Config.new(
    scenes: scenes,
    audio: Obsctl::Config::AudioConfig.new(inputs),
    scene_profiles: scene_profiles,
    active_scene_profile: active_scene_profile
  )
end

describe Obsctl::Server::SnapshotAssembler do
  describe ".scenes" do
    it "stamps the configured alias, shortcut and group onto OBS scene names" do
      config = assembler_config(scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera", "main", "1", "primary"),
      ])

      scenes = Obsctl::Server::SnapshotAssembler.scenes(config, ["Main Camera", "BRB"], "Main Camera")

      scenes.map(&.name).should eq(["Main Camera", "BRB"])
      scenes[0].alias.should eq("main")
      scenes[0].shortcut.should eq("1")
      scenes[0].group.should eq("primary")
      scenes[0].active.should be_true
      # A scene OBS reports but the config says nothing about still appears,
      # unnamed and unbound.
      scenes[1].alias.should be_nil
      scenes[1].active.should be_false
    end

    it "marks nothing active when OBS reports no current scene" do
      scenes = Obsctl::Server::SnapshotAssembler.scenes(assembler_config, ["Main Camera"], nil)

      scenes[0].active.should be_false
    end

    it "hides the scenes the config marks hidden when no profile is active" do
      config = assembler_config(scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera"),
        Obsctl::Config::SceneConfig.new("BRB", hidden: true),
      ])

      scenes = Obsctl::Server::SnapshotAssembler.scenes(config, ["Main Camera", "BRB"], "Main Camera")

      scenes.map(&.hidden).should eq([false, true])
    end

    it "lets the active scene profile replace the per-scene hidden flags" do
      config = assembler_config(
        scenes: [
          Obsctl::Config::SceneConfig.new("Main Camera"),
          Obsctl::Config::SceneConfig.new("BRB", hidden: true),
        ],
        scene_profiles: [
          Obsctl::Config::SceneProfileConfig.new("streaming", ["Main Camera"]),
        ],
        active_scene_profile: "streaming"
      )

      scenes = Obsctl::Server::SnapshotAssembler.scenes(config, ["Main Camera", "BRB"], "BRB")

      # The profile's list is the whole answer: "BRB" is hidden in the config
      # and visible here, because the profile does not name it.
      scenes.map(&.hidden).should eq([true, false])
    end
  end

  describe ".audio_state" do
    it "stamps the configured alias and shortcut onto one input's readings" do
      config = assembler_config(inputs: [
        Obsctl::Config::AudioInputConfig.new("Mic/Aux", "mic", "m"),
      ])

      state = Obsctl::Server::SnapshotAssembler.audio_state(
        config,
        "Mic/Aux",
        false,
        {mul: 0.7, db: -3.0, percent: 70}
      )

      state.name.should eq("Mic/Aux")
      state.alias.should eq("mic")
      state.shortcut.should eq("m")
      state.muted.should be_false
      state.volume_mul.should eq(0.7)
      state.volume_db.should eq(-3.0)
      state.volume_percent.should eq(70)
    end

    it "carries an unconfigured input through with nothing stamped on it" do
      state = Obsctl::Server::SnapshotAssembler.audio_state(
        assembler_config,
        "Desktop Audio",
        nil,
        {mul: nil, db: nil, percent: nil}
      )

      state.alias.should be_nil
      state.shortcut.should be_nil
      state.muted.should be_nil
      state.volume_percent.should be_nil
    end
  end

  describe ".scene_profiles" do
    it "lists the configured profiles and the active one by its stored spelling" do
      config = assembler_config(
        scene_profiles: [
          Obsctl::Config::SceneProfileConfig.new("streaming", ["BRB"]),
          Obsctl::Config::SceneProfileConfig.new("recording"),
        ],
        active_scene_profile: "STREAMING"
      )

      listing = Obsctl::Server::SnapshotAssembler.scene_profiles(config)

      listing[:profiles].map(&.name).should eq(["streaming", "recording"])
      listing[:profiles][0].hidden.should eq(["BRB"])
      # Names match case-insensitively, but what goes out is the spelling that
      # is in the list beside it.
      listing[:active].should eq("streaming")
    end

    it "advertises no active profile when the config names one that is gone" do
      config = assembler_config(
        scene_profiles: [Obsctl::Config::SceneProfileConfig.new("streaming")],
        active_scene_profile: "deleted"
      )

      Obsctl::Server::SnapshotAssembler.scene_profiles(config)[:active].should be_nil
    end
  end
end
