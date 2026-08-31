require "../config/config"
require "../obs/state/audio_state"
require "../obs/state/obs_snapshot"
require "../obs/state/scene_profile_state"
require "../obs/state/scene_state"

module Obsctl
  module Server
    # Builds the snapshot the daemon publishes, out of what OBS reports and
    # what obsctl's own config says about it.
    #
    # `OBS::Client` is the anticorruption layer for obs-websocket: it answers
    # questions about OBS and keeps the vendor's peculiarities out of
    # everything else. That a scene OBS calls "BRB Loop" is displayed as
    # "brb", is reachable with the `3` key, and is hidden because a scene
    # profile says so are not questions about OBS at all -- they are obsctl's
    # own policy, and OBS is never asked about them. Applying that policy here
    # is what lets it be read and exercised without a websocket; it used to be
    # reachable only through a live connection, which is why
    # `spec/support/scene_profiles.cr` grew a hand-written second copy of it.
    #
    # `compose` names `OBS::Client` without this file pulling `obs/client` in.
    # That require is the daemon's marker for "this file owns an OBS
    # connection", and `spec/obsctl/architecture_boundary_spec.cr` allows it in
    # the supervisor and nowhere else under `src/obsctl/server/`. Naming the
    # type in a signature is not owning one, and every caller of `compose` has
    # already brought the client in.
    module SnapshotAssembler
      extend self

      # Fetches a full state snapshot for publication to local IPC clients.
      def compose(client : OBS::Client, config : Config::Config) : OBS::State::ObsSnapshot
        version_data = client.version
        scene_data = client.scene_readings
        scene_states = scenes(config, scene_data[:scene_names], scene_data[:current_scene])
        audio = audio_inputs(client, config)
        profile_data = client.profiles
        collection_data = client.scene_collections
        scene_profile_data = scene_profiles(config)
        output = client.output_details
        OBS::State::ObsSnapshot.new(
          connected: true,
          obs_studio_version: version_data["obsVersion"]?.try(&.as_s),
          obs_websocket_version: version_data["obsWebSocketVersion"]?.try(&.as_s),
          current_scene: scene_data[:current_scene],
          scenes: scene_states,
          audio_inputs: audio,
          output: output[:state],
          profiles: profile_data[:names],
          current_profile: profile_data[:current],
          scene_collections: collection_data[:names],
          current_scene_collection: collection_data[:current],
          scene_profiles: scene_profile_data[:profiles],
          active_scene_profile: scene_profile_data[:active],
          stats: client.stats,
          stream_duration_ms: output[:stream_duration_ms],
          record_duration_ms: output[:record_duration_ms]
        )
      end

      # Stamps obsctl's per-scene settings onto the scene names OBS reported.
      def scenes(config : Config::Config, scene_names : Array(String), current : String?) : Array(OBS::State::SceneState)
        # Resolved once for the whole list rather than per scene, and read from
        # here rather than from `configured.hidden`: an active scene profile
        # replaces the per-scene flags outright, so this is the single point at
        # which hidden-ness enters a snapshot. Every client reads the answer
        # rather than working it out again.
        visibility = config.scene_visibility
        scene_names.map do |name|
          configured = config.scenes.find { |scene| scene.name == name }
          OBS::State::SceneState.new(
            name: name,
            alias: configured.try(&.alias),
            shortcut: configured.try(&.shortcut),
            group: configured.try(&.group),
            active: current == name,
            hidden: visibility.hidden?(name)
          )
        end
      end

      # The whole audio matrix: every input OBS agrees to describe, stamped
      # with obsctl's settings for it.
      def audio_inputs(client : OBS::Client, config : Config::Config) : Array(OBS::State::AudioState)
        client.input_names.compact_map do |name|
          client.audio_readings(name).try do |reading|
            audio_state(config, name, reading[:muted], reading[:volume])
          end
        end
      end

      # Stamps obsctl's per-input settings onto one input's OBS readings.
      def audio_state(
        config : Config::Config,
        name : String,
        muted : Bool?,
        volume : NamedTuple(mul: Float64?, db: Float64?, percent: Int32?),
      ) : OBS::State::AudioState
        configured = config.audio.inputs.find { |input| input.name == name }
        OBS::State::AudioState.new(
          name: name,
          alias: configured.try(&.alias),
          shortcut: configured.try(&.shortcut),
          muted: muted,
          volume_mul: volume[:mul],
          volume_db: volume[:db],
          volume_percent: volume[:percent]
        )
      end

      # obsctl's own scene profiles, as clients see them. Read straight from the
      # config: they are obsctl state, not OBS state, so nothing is asked of OBS
      # here and they stay reportable while the connection is down.
      def scene_profiles(config : Config::Config) : {profiles: Array(OBS::State::SceneProfileState), active: String?}
        profiles = config.scene_profiles.map do |profile|
          OBS::State::SceneProfileState.new(profile.name, profile.hidden)
        end
        # The stored spelling, and `nil` when the config names a profile that no
        # longer exists: the snapshot must never advertise an active profile
        # that is missing from the list beside it.
        {profiles: profiles, active: config.active_scene_profile_config.try(&.name)}
      end
    end
  end
end
