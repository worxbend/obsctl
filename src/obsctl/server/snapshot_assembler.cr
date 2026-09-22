require "../config/config"
require "../state/audio_state"
require "../state/obs_snapshot"
require "../state/scene_profile_state"
require "../state/scene_state"

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
      def compose(client : OBS::Client, config : Config::Config) : State::ObsSnapshot
        version_data = client.version
        scene_data = client.scene_readings
        configured_scenes = configured_scenes_by_name(config)
        configured_audio_inputs = configured_audio_inputs_by_name(config)
        scene_states = scenes(config, scene_data[:scene_names], scene_data[:current_scene], configured_scenes)
        audio = audio_inputs(client, config, configured_audio_inputs)
        profile_data = client.profiles
        collection_data = client.scene_collections
        scene_profile_data = scene_profiles(config)
        output = client.output_details
        State::ObsSnapshot.new(
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
      def scenes(
        config : Config::Config,
        scene_names : Array(String),
        current : String?,
        configured : Hash(String, Config::SceneConfig)? = nil,
      ) : Array(State::SceneState)
        # Resolved once for the whole list rather than per scene, and read from
        # here rather than from `configured.hidden`: an active scene profile
        # replaces the per-scene flags outright, so this is the single point at
        # which hidden-ness enters a snapshot. Every client reads the answer
        # rather than working it out again.
        visibility = config.scene_visibility
        configured_scenes = configured || configured_scenes_by_name(config)
        scene_names.map do |name|
          scene = configured_scenes[name]?
          State::SceneState.new(
            name: name,
            alias: scene.try(&.alias),
            shortcut: scene.try(&.shortcut),
            group: scene.try(&.group),
            active: current == name,
            hidden: visibility.hidden?(name)
          )
        end
      end

      # The whole audio matrix: every input OBS agrees to describe, stamped
      # with obsctl's settings for it.
      def audio_inputs(
        client : OBS::Client,
        config : Config::Config,
        configured : Hash(String, Config::AudioInputConfig)? = nil,
      ) : Array(State::AudioState)
        configured_audio_inputs = configured || configured_audio_inputs_by_name(config)
        client.input_names.compact_map do |name|
          client.audio_readings(name).try do |reading|
            audio_state(name, reading[:muted], reading[:volume], configured_audio_inputs[name]?)
          end
        end
      end

      # Stamps obsctl's per-input settings onto one input's OBS readings.
      def audio_state(
        config : Config::Config,
        name : String,
        muted : Bool?,
        volume : NamedTuple(mul: Float64?, db: Float64?, percent: Int32?),
      ) : State::AudioState
        audio_state(name, muted, volume, configured_audio_inputs_by_name(config)[name]?)
      end

      # Stamps obsctl's per-input settings onto one input's OBS readings.
      def audio_state(
        name : String,
        muted : Bool?,
        volume : NamedTuple(mul: Float64?, db: Float64?, percent: Int32?),
        configured : Config::AudioInputConfig? = nil,
      ) : State::AudioState
        State::AudioState.new(
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
      def scene_profiles(config : Config::Config) : {profiles: Array(State::SceneProfileState), active: String?}
        profiles = config.scene_profiles.map do |profile|
          State::SceneProfileState.new(profile.name, profile.hidden)
        end
        # The stored spelling, and `nil` when the config names a profile that no
        # longer exists: the snapshot must never advertise an active profile
        # that is missing from the list beside it.
        {profiles: profiles, active: config.active_scene_profile_config.try(&.name)}
      end

      private def configured_scenes_by_name(config : Config::Config) : Hash(String, Config::SceneConfig)
        config.scenes.each_with_object({} of String => Config::SceneConfig) do |scene, configured|
          configured[scene.name] = scene
        end
      end

      private def configured_audio_inputs_by_name(config : Config::Config) : Hash(String, Config::AudioInputConfig)
        config.audio.inputs.each_with_object({} of String => Config::AudioInputConfig) do |input, configured|
          configured[input.name] = input
        end
      end
    end
  end
end
