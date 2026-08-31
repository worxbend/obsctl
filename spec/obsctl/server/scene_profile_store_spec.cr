require "../../spec_helper"
require "../../../src/obsctl/server/scene_profile_store"

# The scene-profile rules on their own: where a save lands, whether that counts
# as a rename, and where the active pointer ends up.
#
# `scene_profile_commands_spec.cr` drives the same rules through the daemon,
# which needs a state store, a supervisor and an IPC request to say anything at
# all. None of that is involved in deciding these answers, so the store is
# exercised here with a config, a tempfile and a refresh proc that counts calls.

private def store_config_path : String
  File.join(Dir.tempdir, "obsctl-scene-profile-store-#{Random.rand(1_000_000)}.yml")
end

private def store_config(
  profiles : Array(Obsctl::Config::SceneProfileConfig) = [] of Obsctl::Config::SceneProfileConfig,
  active : String? = nil,
) : Obsctl::Config::Config
  Obsctl::Config::Config.new(
    connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
    scene_profiles: profiles,
    active_scene_profile: active
  )
end

private def stored(name : String, hidden : Array(String) = [] of String)
  Obsctl::Config::SceneProfileConfig.new(name: name, hidden: hidden)
end

describe Obsctl::Server::SceneProfileStore do
  it "adopts the written config in place and republishes the snapshot" do
    path = store_config_path
    config = store_config([stored("streaming", ["Cam"])])
    refreshes = 0
    store = Obsctl::Server::SceneProfileStore.new(config, path, -> { refreshes += 1; nil })

    store.set("STREAMING")

    # The caller's spelling looked the profile up but did not rewrite it.
    config.active_scene_profile.should eq("streaming")
    Obsctl::Config::Config.from_yaml(File.read(path)).active_scene_profile.should eq("streaming")
    refreshes.should eq(1)
  ensure
    File.delete?(path.not_nil!)
  end

  it "leaves the daemon's config untouched when a save is refused" do
    path = store_config_path
    config = store_config([stored("streaming"), stored("editing")])
    store = Obsctl::Server::SceneProfileStore.new(config, path, -> { })

    expect_raises(Obsctl::Domain::ConfigInvalid, "scene profile already exists: editing") do
      store.save("editing", [] of String, rename_from: "streaming")
    end

    config.scene_profiles.map(&.name).should eq(["streaming", "editing"])
    File.exists?(path).should be_false
  ensure
    File.delete?(path.not_nil!)
  end

  it "carries the active pointer across a rename" do
    path = store_config_path
    config = store_config([stored("streaming", ["Cam"])], active: "streaming")
    store = Obsctl::Server::SceneProfileStore.new(config, path, -> { })

    saved = store.save("live", ["Cam"], rename_from: "streaming")

    saved.created.should be_false
    saved.renamed.should be_true
    saved.active.should be_true
    config.active_scene_profile.should eq("live")
    config.scene_profiles.map(&.name).should eq(["live"])
  ensure
    File.delete?(path.not_nil!)
  end

  it "treats saving over the same name as a replacement, not a rename" do
    path = store_config_path
    config = store_config([stored("streaming", ["Cam"])])
    store = Obsctl::Server::SceneProfileStore.new(config, path, -> { })

    saved = store.save("Streaming", ["BRB Loop"], nil)

    saved.created.should be_false
    saved.renamed.should be_false
    # The caller's spelling wins on a save, unlike on a lookup: a save is the
    # caller stating what the profile is called from now on.
    config.scene_profiles.map(&.name).should eq(["Streaming"])
    config.scene_profiles.first.hidden.should eq(["BRB Loop"])
  ensure
    File.delete?(path.not_nil!)
  end

  it "switches filtering off when the profile in effect is deleted" do
    path = store_config_path
    config = store_config([stored("streaming"), stored("editing")], active: "streaming")
    store = Obsctl::Server::SceneProfileStore.new(config, path, -> { })

    store.delete("editing").deactivated.should be_false
    config.active_scene_profile.should eq("streaming")

    store.delete("streaming").deactivated.should be_true
    config.active_scene_profile.should be_nil
  ensure
    File.delete?(path.not_nil!)
  end

  it "collapses hidden names differing only in case or padding" do
    store = Obsctl::Server::SceneProfileStore.new(store_config, store_config_path, -> { })

    store.normalize_hidden(["Cam", "cam", "  CAM  ", "Main"]).should eq(["Cam", "Main"])
  end
end
