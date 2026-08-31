require "../../src/obsctl/domain/scene_profiles"
require "../../src/obsctl/tui/model"

# Puts scene profiles on a model the way the daemon does.
#
# The dashboard no longer decides which scenes are hidden: the daemon resolves
# the active profile against the per-scene `hidden` flags and ships the answer
# on each scene, and `Model#scenes` just drops the ones already marked hidden.
# A spec that only set `snapshot.scene_profiles` would therefore see an
# unfiltered scene list and prove nothing, so this helper does both halves --
# it lists the profiles *and* re-resolves `hidden` -- which is exactly the pair
# `Server::SnapshotAssembler.scenes` and `.scene_profiles` produce together.
#
# Kept in one place because getting only half of it right is the failure mode
# that would make these specs pass against a dashboard that had gone back to
# filtering on its own.
# `baseline_hidden` names the scenes the config marks `hidden:` -- the flags
# that apply when no profile is active. It defaults to none, and is passed
# explicitly rather than read back off the snapshot because the snapshot's
# flags are the *resolved* answer: reading them back would make each call
# resolve against the previous call's output, so switching a profile off would
# leave the scenes it hid still hidden.
def set_scene_profiles(
  model : Obsctl::TUI::Model,
  profiles : Obsctl::TUI::SceneProfiles,
  baseline_hidden : Enumerable(String) = [] of String,
) : Nil
  snapshot = model.snapshot
  raise "set_scene_profiles needs a snapshot on the model" unless snapshot

  active = profiles.active_profile
  hidden_baseline = baseline_hidden.to_set
  visibility = Obsctl::Domain::SceneVisibility.resolve(
    snapshot.scenes.map { |scene| {scene.name, hidden_baseline.includes?(scene.name)} },
    active.try(&.hidden.to_a)
  )

  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: snapshot.connected,
    obs_studio_version: snapshot.obs_studio_version,
    obs_websocket_version: snapshot.obs_websocket_version,
    current_scene: snapshot.current_scene,
    scenes: snapshot.scenes.map do |scene|
      Obsctl::OBS::State::SceneState.new(
        name: scene.name,
        alias: scene.alias,
        shortcut: scene.shortcut,
        group: scene.group,
        active: scene.active,
        hidden: visibility.hidden?(scene.name)
      )
    end,
    audio_inputs: snapshot.audio_inputs,
    output: snapshot.output,
    profiles: snapshot.profiles,
    current_profile: snapshot.current_profile,
    scene_collections: snapshot.scene_collections,
    current_scene_collection: snapshot.current_scene_collection,
    scene_profiles: profiles.profiles.map do |profile|
      Obsctl::OBS::State::SceneProfileState.new(profile.name, profile.hidden.to_a.sort!)
    end,
    # `nil` rather than the name when the config names a profile that is not in
    # the list, the way the daemon refuses to advertise one.
    active_scene_profile: active.try(&.name),
    stats: snapshot.stats,
    stream_bitrate_kbps: snapshot.stream_bitrate_kbps,
    stream_duration_ms: snapshot.stream_duration_ms,
    record_duration_ms: snapshot.record_duration_ms,
    last_error: snapshot.last_error,
    updated_at: snapshot.updated_at
  )
end

# A minimal connected snapshot for specs that only care about scene profiles.
#
# `set_scene_profiles` needs a snapshot to fold profiles into, because the
# dashboard reads them from there now rather than from a field of its own.
def scene_profile_spec_snapshot(scene_names = ["Main", "Cam", "Utility Cam", "BRB Loop"])
  Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: scene_names.first?,
    scenes: scene_names.map_with_index do |name, index|
      Obsctl::OBS::State::SceneState.new(name, active: index == 0, hidden: false)
    end,
    audio_inputs: [] of Obsctl::OBS::State::AudioState
  )
end
