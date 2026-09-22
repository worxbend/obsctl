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

  model.snapshot = Obsctl::State::ObsSnapshot.new(
    connected: snapshot.connected,
    obs_studio_version: snapshot.obs_studio_version,
    obs_websocket_version: snapshot.obs_websocket_version,
    current_scene: snapshot.current_scene,
    scenes: snapshot.scenes.map do |scene|
      Obsctl::State::SceneState.new(
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
      Obsctl::State::SceneProfileState.new(profile.name, profile.hidden.to_a.sort!)
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
  Obsctl::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: scene_names.first?,
    scenes: scene_names.map_with_index do |name, index|
      Obsctl::State::SceneState.new(name, active: index == 0, hidden: false)
    end,
    audio_inputs: [] of Obsctl::State::AudioState
  )
end

# Builds a `SceneProfiles` value straight from the finished list.
#
# `TUI::SceneProfiles` is a read model with no `upsert`, `delete` or `activate`
# on it -- the daemon owns every write -- so a spec states the list it wants
# rather than replaying the sequence of edits that would have produced it,
# which is also how the dashboard receives it: as a finished snapshot. Each
# entry is a profile name and the scenes it hides; `active` names the profile
# in effect and defaults to none.
def scene_profiles_fixture(
  entries : Array(Tuple(String, Array(String))) = [] of Tuple(String, Array(String)),
  active : String? = nil,
) : Obsctl::TUI::SceneProfiles
  Obsctl::TUI::SceneProfiles.new(
    entries.map { |(name, hidden)| Obsctl::TUI::SceneProfile.new(name, hidden.to_set) },
    active
  )
end

# The same list with one profile added (or replaced, when the name is already
# there) and the same list with one profile taken out.
#
# For the specs that are *about* a list changing -- a cursor that has to be
# pulled back in after a profile is deleted, for instance -- where restating
# the shorter list would hide the very thing under test. `without_profile`
# drops the `active` pointer along with the profile it named, the way the
# daemon does, so it never leaves the config naming a profile that is gone.
def with_profile(
  profiles : Obsctl::TUI::SceneProfiles,
  name : String,
  hidden : Enumerable(String) = [] of String,
) : Obsctl::TUI::SceneProfiles
  updated = profiles.profiles.dup
  profile = Obsctl::TUI::SceneProfile.new(name, hidden.to_set)
  if index = profiles.index_of(name)
    updated[index] = profile
  else
    updated << profile
  end
  Obsctl::TUI::SceneProfiles.new(updated, profiles.active)
end

def without_profile(profiles : Obsctl::TUI::SceneProfiles, name : String) : Obsctl::TUI::SceneProfiles
  Obsctl::TUI::SceneProfiles.new(
    profiles.profiles.reject { |profile| profile.name == name },
    profiles.active == name ? nil : profiles.active
  )
end
