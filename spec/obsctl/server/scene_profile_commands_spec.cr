require "../../spec_helper"
require "../../../src/obsctl/server/command_executor"

# The five daemon-side scene-profile commands.
#
# They are the reason the feature is not a dashboard-only one: the daemon owns
# the config file and the snapshot, so a profile switched here reaches every
# client at once, and the CLI and the dashboard cannot disagree about which
# scenes are hidden.

private def profile_config_path : String
  File.join(Dir.tempdir, "obsctl-scene-profile-#{Random.rand(1_000_000)}.yml")
end

private def profile_config(
  profiles : Array(Obsctl::Config::SceneProfileConfig) = [] of Obsctl::Config::SceneProfileConfig,
  active : String? = nil,
  scenes : Array(String) = ["Main", "Cam", "Utility Cam", "BRB Loop"],
) : Obsctl::Config::Config
  Obsctl::Config::Config.new(
    connection: Obsctl::Config::ConnectionConfig.new(password_env: ""),
    scenes: scenes.map { |name| Obsctl::Config::SceneConfig.new(name: name) },
    scene_profiles: profiles,
    active_scene_profile: active
  )
end

private def profile(name : String, hidden : Array(String) = [] of String)
  Obsctl::Config::SceneProfileConfig.new(name: name, hidden: hidden)
end

private def profile_executor(config : Obsctl::Config::Config, path : String)
  state = Obsctl::Server::StateStore.new
  Obsctl::Server::CommandExecutor.new(
    config,
    path,
    state,
    Obsctl::Server::ObsSupervisor.new(config, state),
    "/tmp/obsctl.sock"
  )
end

private def run(config : Obsctl::Config::Config, path : String, payload : Obsctl::IPC::CommandPayload)
  profile_executor(config, path).execute(
    Obsctl::IPC::Request.new("req-000001", Obsctl::IPC::Request::TYPE_COMMAND, payload)
  )
end

private def set_payload(target : String)
  Obsctl::IPC::CommandPayload.new(name: Obsctl::IPC::CommandName::SET_SCENE_PROFILE, target: target)
end

private def save_payload(target : String, hidden : Array(String), rename_from : String? = nil)
  Obsctl::IPC::CommandPayload.new(
    name: Obsctl::IPC::CommandName::SAVE_SCENE_PROFILE,
    hidden: hidden,
    rename_from: rename_from,
    target: target
  )
end

describe "set_scene_profile" do
  it "activates the profile and writes it to the config file" do
    path = profile_config_path
    config = profile_config([profile("streaming", ["Cam"])])

    response = run(config, path, set_payload("streaming"))

    response.ok.should be_true
    result = response.result.not_nil!
    result["message"].as_s.should eq("scene profile set: streaming")
    # `listed` is what the profile names; `hidden` is how many of those really
    # disappear, which differs once a profile outlives a scene. With no
    # snapshot yet there is nothing to intersect against, so it falls back to
    # the listed count rather than reporting a confident zero.
    result["listed"].as_i.should eq(1)
    result["hidden"].as_i.should eq(1)
    Obsctl::Config::Config.from_yaml(File.read(path)).active_scene_profile.should eq("streaming")
  ensure
    File.delete?(path.not_nil!)
  end

  it "stores the profile's own spelling, not the caller's" do
    # Lookup is case-insensitive, but the config entry is the record of what
    # the profile is called and must not be rewritten on every use.
    path = profile_config_path
    config = profile_config([profile("Streaming", ["Cam"])])

    run(config, path, set_payload("  streaming  ")).ok.should be_true

    Obsctl::Config::Config.from_yaml(File.read(path)).active_scene_profile.should eq("Streaming")
  ensure
    File.delete?(path.not_nil!)
  end

  it "refuses a name no profile answers to, and writes nothing" do
    path = profile_config_path
    config = profile_config([profile("streaming")])

    response = run(config, path, set_payload("podcast"))

    response.ok.should be_false
    response.error.not_nil!.message.should eq("scene profile not found: podcast")
    File.exists?(path).should be_false
  ensure
    File.delete?(path.not_nil!)
  end
end

describe "clear_scene_profile" do
  it "switches filtering off without forgetting the saved profiles" do
    path = profile_config_path
    config = profile_config([profile("streaming", ["Cam"])], active: "streaming")

    response = run(config, path, Obsctl::IPC::CommandPayload.new(name: Obsctl::IPC::CommandName::CLEAR_SCENE_PROFILE))

    response.ok.should be_true
    response.result.not_nil!["message"].as_s.should eq("scene profile cleared")
    written = Obsctl::Config::Config.from_yaml(File.read(path))
    written.active_scene_profile.should be_nil
    written.scene_profiles.map(&.name).should eq(["streaming"])
  ensure
    File.delete?(path.not_nil!)
  end

  it "is not an error when nothing was active" do
    # "Stop filtering" is a statement about the state we want, not the one we
    # are in.
    path = profile_config_path

    run(profile_config, path, Obsctl::IPC::CommandPayload.new(name: Obsctl::IPC::CommandName::CLEAR_SCENE_PROFILE)).ok.should be_true
  ensure
    File.delete?(path.not_nil!)
  end
end

describe "save_scene_profile" do
  it "appends a profile that is new, and reports it as created" do
    path = profile_config_path

    response = run(profile_config, path, save_payload("streaming", ["Cam"]))

    result = response.result.not_nil!
    result["message"].as_s.should eq("scene profile saved: streaming")
    result["created"].as_bool.should be_true
    result["renamed"].as_bool.should be_false
    # Saving never changes which profile is in effect: the editor lets a user
    # work on a profile they are not using.
    result["active"].as_bool.should be_false
    Obsctl::Config::Config.from_yaml(File.read(path)).scene_profiles.map(&.name).should eq(["streaming"])
  ensure
    File.delete?(path.not_nil!)
  end

  it "replaces a profile of the same name where it stands" do
    path = profile_config_path
    config = profile_config([profile("streaming", ["Cam"]), profile("editing")])

    response = run(config, path, save_payload("streaming", ["BRB Loop"]))

    response.result.not_nil!["created"].as_bool.should be_false
    written = Obsctl::Config::Config.from_yaml(File.read(path))
    # Still first: replacing must not move the row the reader was looking at.
    written.scene_profiles.map(&.name).should eq(["streaming", "editing"])
    written.scene_profiles.first.hidden.should eq(["BRB Loop"])
  ensure
    File.delete?(path.not_nil!)
  end

  it "replaces a profile whose name differs only in case, adopting the new spelling" do
    # Pinned because it is what any client saving without `rename_from` gets:
    # names match case-insensitively here, so "Streaming" is not a second
    # profile beside "streaming" -- it is the same one, saved over. The
    # dashboard's own duplicate check has to ask the question the same way or
    # it waves through a save that silently discards someone else's scenes.
    path = profile_config_path
    config = profile_config([profile("streaming", ["Cam"]), profile("editing")])

    response = run(config, path, save_payload("Streaming", ["BRB Loop"]))

    result = response.result.not_nil!
    result["created"].as_bool.should be_false
    result["renamed"].as_bool.should be_false
    written = Obsctl::Config::Config.from_yaml(File.read(path))
    written.scene_profiles.map(&.name).should eq(["Streaming", "editing"])
    written.scene_profiles.first.hidden.should eq(["BRB Loop"])
  ensure
    File.delete?(path.not_nil!)
  end

  it "moves the entry and carries the active pointer with it on a rename" do
    # The whole reason `rename_from` exists: a save-then-delete pair would
    # rewrite the file twice and switch filtering off on the way, because
    # deleting the active profile deactivates it.
    path = profile_config_path
    config = profile_config([profile("streaming", ["Cam"]), profile("editing")], active: "streaming")

    response = run(config, path, save_payload("live", ["Cam"], rename_from: "streaming"))

    result = response.result.not_nil!
    result["renamed"].as_bool.should be_true
    result["active"].as_bool.should be_true
    written = Obsctl::Config::Config.from_yaml(File.read(path))
    written.scene_profiles.map(&.name).should eq(["live", "editing"])
    written.active_scene_profile.should eq("live")
  ensure
    File.delete?(path.not_nil!)
  end

  it "refuses a rename onto a name another profile answers to, before writing" do
    path = profile_config_path
    config = profile_config([profile("streaming"), profile("editing")])

    response = run(config, path, save_payload("editing", [] of String, rename_from: "streaming"))

    response.ok.should be_false
    response.error.not_nil!.message.should eq("scene profile already exists: editing")
    # Nothing written and no backup left: a refused save leaves no trace.
    File.exists?(path).should be_false
  ensure
    File.delete?(path.not_nil!)
  end

  it "keeps an empty hidden list as a profile that hides nothing" do
    path = profile_config_path

    run(profile_config, path, save_payload("everything", [] of String)).ok.should be_true

    Obsctl::Config::Config.from_yaml(File.read(path)).scene_profiles.first.hidden.should be_empty
  ensure
    File.delete?(path.not_nil!)
  end

  it "collapses names differing only in case, keeping the first spelling" do
    path = profile_config_path

    run(profile_config, path, save_payload("streaming", ["Cam", "cam", "  CAM  "])).ok.should be_true

    Obsctl::Config::Config.from_yaml(File.read(path)).scene_profiles.first.hidden.should eq(["Cam"])
  ensure
    File.delete?(path.not_nil!)
  end

  it "refuses a hidden list longer than the cap" do
    # The cap keeps the request, and the snapshot it produces, inside the IPC
    # line limit.
    path = profile_config_path
    too_many = Array.new(Obsctl::Server::CommandExecutor::MAX_HIDDEN_SCENES_PER_PROFILE + 1) { |index| "Scene #{index}" }

    response = run(profile_config, path, save_payload("streaming", too_many))

    response.ok.should be_false
    response.error.not_nil!.message.should eq("hidden must name at most 128 scenes")
  ensure
    File.delete?(path.not_nil!)
  end

  it "refuses an unusable name, saying which argument was wrong" do
    path = profile_config_path

    run(profile_config, path, save_payload("  ", [] of String)).error.not_nil!
      .message.should eq("target must not be blank")
    run(profile_config, path, save_payload("streaming", ["bad\nname"])).error.not_nil!
      .message.should eq("hidden scene must not contain control characters")
  ensure
    File.delete?(path.not_nil!)
  end
end

describe "delete_scene_profile" do
  it "removes the profile and says whether that switched filtering off" do
    path = profile_config_path
    config = profile_config([profile("streaming", ["Cam"]), profile("editing")], active: "streaming")

    response = run(config, path, Obsctl::IPC::CommandPayload.new(
      name: Obsctl::IPC::CommandName::DELETE_SCENE_PROFILE, target: "streaming"
    ))

    result = response.result.not_nil!
    result["message"].as_s.should eq("scene profile deleted: streaming")
    result["deactivated"].as_bool.should be_true
    written = Obsctl::Config::Config.from_yaml(File.read(path))
    written.scene_profiles.map(&.name).should eq(["editing"])
    # Cleared rather than left naming something the config no longer has.
    written.active_scene_profile.should be_nil
  ensure
    File.delete?(path.not_nil!)
  end

  it "leaves an unrelated active profile alone" do
    path = profile_config_path
    config = profile_config([profile("streaming"), profile("editing")], active: "streaming")

    response = run(config, path, Obsctl::IPC::CommandPayload.new(
      name: Obsctl::IPC::CommandName::DELETE_SCENE_PROFILE, target: "editing"
    ))

    response.result.not_nil!["deactivated"].as_bool.should be_false
    Obsctl::Config::Config.from_yaml(File.read(path)).active_scene_profile.should eq("streaming")
  ensure
    File.delete?(path.not_nil!)
  end
end

describe "list_scene_profiles" do
  it "reports every profile and which one is in effect" do
    path = profile_config_path
    config = profile_config([profile("streaming", ["Cam"]), profile("editing")], active: "streaming")

    response = run(config, path, Obsctl::IPC::CommandPayload.new(name: Obsctl::IPC::CommandName::LIST_SCENE_PROFILES))

    result = response.result.not_nil!
    result["active"].as_s.should eq("streaming")
    result["profiles"].as_a.map(&.["name"].as_s).should eq(["streaming", "editing"])
    result["profiles"][0]["hidden"].as_a.map(&.as_s).should eq(["Cam"])
    # Answered from memory, so a listing never queues behind a save and never
    # touches the file.
    File.exists?(path).should be_false
  ensure
    File.delete?(path.not_nil!)
  end

  it "reports no active profile when the config names one that is not defined" do
    path = profile_config_path
    config = profile_config([profile("streaming")], active: "podcast")

    response = run(config, path, Obsctl::IPC::CommandPayload.new(name: Obsctl::IPC::CommandName::LIST_SCENE_PROFILES))

    response.result.not_nil!["active"].raw.should be_nil
  ensure
    File.delete?(path.not_nil!)
  end
end
