require "json"
require "../obs/protocol/json_value"
require "../obs/state/obs_snapshot"
require "../obs/state/scene_state"
require "../obs/state/audio_state"
require "../obs/state/output_state"
require "../obs/state/obs_stats"

module Obsctl
  module IPC
    # The `state` topic payload, in both directions.
    #
    # This is the published language for OBS state: the daemon encodes a
    # snapshot into it, and the dashboard decodes it back. The two halves are
    # one contract and now live in one file, because they only work if they
    # agree about every key name, and they used to be written a layer apart —
    # the encoder in `Server::StateStore`, the decoder in `TUI::EventApplier` —
    # with nothing but care keeping them in step. `docs/protocol.md` freezes
    # this shape; `spec/obsctl/ipc/state_snapshot_codec_spec.cr` proves a
    # snapshot survives the round trip.
    #
    # Decoding is lenient on purpose. A dashboard may be talking to an older or
    # newer daemon, and a missing optional field should render as "unknown"
    # rather than drop the whole update; a payload that is not a state snapshot
    # at all returns nil.
    module StateSnapshotCodec
      # Converts a snapshot into the stable IPC state-event JSON shape.
      def self.encode(snapshot : OBS::State::ObsSnapshot) : JSON::Any
        JSON.parse({
          connected:                snapshot.connected,
          obs_studio_version:       snapshot.obs_studio_version,
          obs_websocket_version:    snapshot.obs_websocket_version,
          current_scene:            snapshot.current_scene,
          scenes:                   snapshot.scenes.map { |scene| encode_scene(scene) },
          audio_inputs:             snapshot.audio_inputs.map { |input| encode_audio_input(input) },
          output:                   encode_output(snapshot.output),
          profiles:                 snapshot.profiles,
          current_profile:          snapshot.current_profile,
          scene_collections:        snapshot.scene_collections,
          current_scene_collection: snapshot.current_scene_collection,
          scene_profiles:           snapshot.scene_profiles.map { |profile| encode_scene_profile(profile) },
          active_scene_profile:     snapshot.active_scene_profile,
          stats:                    stats_json(snapshot.stats),
          stream_bitrate_kbps:      snapshot.stream_bitrate_kbps,
          stream_duration_ms:       snapshot.stream_duration_ms,
          record_duration_ms:       snapshot.record_duration_ms,
          last_error:               snapshot.last_error,
          updated_at:               snapshot.updated_at.to_rfc3339,
        }.to_json)
      end

      private def self.stats_json(stats : OBS::State::ObsStats?)
        return unless stats
        {
          cpu_usage_percent:            stats.cpu_usage_percent,
          memory_usage_mb:              stats.memory_usage_mb,
          available_disk_space_mb:      stats.available_disk_space_mb,
          active_fps:                   stats.active_fps,
          average_frame_render_time_ms: stats.average_frame_render_time_ms,
          render_skipped_frames:        stats.render_skipped_frames,
          render_total_frames:          stats.render_total_frames,
          output_skipped_frames:        stats.output_skipped_frames,
          output_total_frames:          stats.output_total_frames,
        }
      end

      private def self.encode_scene(scene : OBS::State::SceneState)
        {
          name:     scene.name,
          alias:    scene.alias,
          shortcut: scene.shortcut,
          group:    scene.group,
          active:   scene.active,
          hidden:   scene.hidden,
        }
      end

      private def self.encode_audio_input(input : OBS::State::AudioState)
        {
          name:           input.name,
          alias:          input.alias,
          shortcut:       input.shortcut,
          muted:          input.muted,
          volume_mul:     input.volume_mul,
          volume_db:      input.volume_db,
          volume_percent: input.volume_percent,
        }
      end

      private def self.encode_output(output : OBS::State::OutputState)
        {
          streaming: output.streaming,
          recording: output.recording,
        }
      end

      private def self.encode_scene_profile(profile : OBS::State::SceneProfileState)
        {
          name:   profile.name,
          hidden: profile.hidden,
        }
      end

      def self.decode(data : JSON::Any) : OBS::State::ObsSnapshot?
        OBS::State::ObsSnapshot.new(
          connected: data["connected"].as_bool,
          obs_studio_version: string_field(data, "obs_studio_version"),
          obs_websocket_version: string_field(data, "obs_websocket_version"),
          current_scene: string_field(data, "current_scene"),
          scenes: decode_scenes(data["scenes"]),
          audio_inputs: decode_audio_inputs(data["audio_inputs"]),
          output: decode_output(data["output"]?),
          profiles: string_array(data["profiles"]?),
          current_profile: string_field(data, "current_profile"),
          scene_collections: string_array(data["scene_collections"]?),
          current_scene_collection: string_field(data, "current_scene_collection"),
          # Read leniently, so a snapshot from a daemon that predates scene
          # profiles still renders instead of failing the whole decode.
          scene_profiles: scene_profiles(data["scene_profiles"]?),
          active_scene_profile: string_field(data, "active_scene_profile"),
          stats: decode_stats(data["stats"]?),
          stream_bitrate_kbps: OBS::Protocol::JsonValue.number(data["stream_bitrate_kbps"]?),
          stream_duration_ms: int64_field(data, "stream_duration_ms"),
          record_duration_ms: int64_field(data, "record_duration_ms"),
          last_error: string_field(data, "last_error"),
          updated_at: parsed_time(string_field(data, "updated_at"))
        )
      rescue TypeCastError | KeyError | Time::Format::Error
        nil
      end

      private def self.decode_scenes(data : JSON::Any) : Array(OBS::State::SceneState)
        data.as_a.map { |scene| decode_scene(scene) }
      end

      private def self.decode_scene(scene : JSON::Any) : OBS::State::SceneState
        OBS::State::SceneState.new(
          name: scene["name"].as_s,
          alias: string_field(scene, "alias"),
          shortcut: string_field(scene, "shortcut"),
          group: string_field(scene, "group"),
          active: bool_field(scene, "active") || false,
          hidden: bool_field(scene, "hidden") || false
        )
      end

      private def self.decode_audio_inputs(data : JSON::Any) : Array(OBS::State::AudioState)
        data.as_a.map { |input| decode_audio_input(input) }
      end

      private def self.decode_audio_input(input : JSON::Any) : OBS::State::AudioState
        OBS::State::AudioState.new(
          name: input["name"].as_s,
          alias: string_field(input, "alias"),
          shortcut: string_field(input, "shortcut"),
          muted: bool_field(input, "muted"),
          volume_mul: OBS::Protocol::JsonValue.number(input["volume_mul"]?),
          volume_db: OBS::Protocol::JsonValue.number(input["volume_db"]?),
          volume_percent: int_field(input, "volume_percent")
        )
      end

      private def self.decode_output(data : JSON::Any?) : OBS::State::OutputState
        OBS::State::OutputState.new(
          streaming: data.try { |value| bool_field(value, "streaming") },
          recording: data.try { |value| bool_field(value, "recording") }
        )
      end

      private def self.decode_stats(data : JSON::Any?) : OBS::State::ObsStats?
        return unless data
        return if data.raw.nil?

        OBS::State::ObsStats.new(
          cpu_usage_percent: OBS::Protocol::JsonValue.number(data["cpu_usage_percent"]?) || 0.0,
          memory_usage_mb: OBS::Protocol::JsonValue.number(data["memory_usage_mb"]?) || 0.0,
          available_disk_space_mb: OBS::Protocol::JsonValue.number(data["available_disk_space_mb"]?) || 0.0,
          active_fps: OBS::Protocol::JsonValue.number(data["active_fps"]?) || 0.0,
          average_frame_render_time_ms: OBS::Protocol::JsonValue.number(data["average_frame_render_time_ms"]?) || 0.0,
          render_skipped_frames: int64_field(data, "render_skipped_frames") || 0_i64,
          render_total_frames: int64_field(data, "render_total_frames") || 0_i64,
          output_skipped_frames: int64_field(data, "output_skipped_frames") || 0_i64,
          output_total_frames: int64_field(data, "output_total_frames") || 0_i64
        )
      end

      def self.scene_profiles(data : JSON::Any?) : Array(OBS::State::SceneProfileState)
        entries = data.try(&.as_a?)
        return [] of OBS::State::SceneProfileState unless entries

        entries.compact_map do |entry|
          name = entry["name"]?.try(&.as_s?)
          next unless name

          OBS::State::SceneProfileState.new(name, string_array(entry["hidden"]?))
        end
      end

      def self.string_array(data : JSON::Any?) : Array(String)
        data.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      end

      private def self.string_field(data : JSON::Any, key : String) : String?
        data[key]?.try(&.as_s?)
      end

      private def self.bool_field(data : JSON::Any, key : String) : Bool?
        data[key]?.try(&.as_bool?)
      end

      private def self.int_field(data : JSON::Any, key : String) : Int32?
        data[key]?.try(&.as_i?).try(&.to_i32)
      end

      private def self.int64_field(data : JSON::Any, key : String) : Int64?
        data[key]?.try(&.as_i64?)
      end

      private def self.parsed_time(value : String?) : Time
        value ? Time.parse_rfc3339(value) : Time.utc
      end
    end
  end
end
