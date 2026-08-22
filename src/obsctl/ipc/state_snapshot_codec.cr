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
          connected:             snapshot.connected,
          obs_studio_version:    snapshot.obs_studio_version,
          obs_websocket_version: snapshot.obs_websocket_version,
          current_scene:         snapshot.current_scene,
          scenes:                snapshot.scenes.map do |scene|
            {
              name:     scene.name,
              alias:    scene.alias,
              shortcut: scene.shortcut,
              group:    scene.group,
              active:   scene.active,
              hidden:   scene.hidden,
            }
          end,
          audio_inputs: snapshot.audio_inputs.map do |input|
            {
              name:           input.name,
              alias:          input.alias,
              shortcut:       input.shortcut,
              muted:          input.muted,
              volume_mul:     input.volume_mul,
              volume_db:      input.volume_db,
              volume_percent: input.volume_percent,
            }
          end,
          output: {
            streaming: snapshot.output.streaming,
            recording: snapshot.output.recording,
          },
          profiles:                 snapshot.profiles,
          current_profile:          snapshot.current_profile,
          scene_collections:        snapshot.scene_collections,
          current_scene_collection: snapshot.current_scene_collection,
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

      def self.decode(data : JSON::Any) : OBS::State::ObsSnapshot?
        scenes = data["scenes"].as_a.map do |scene|
          OBS::State::SceneState.new(
            name: scene["name"].as_s,
            alias: scene["alias"]?.try(&.as_s?),
            shortcut: scene["shortcut"]?.try(&.as_s?),
            group: scene["group"]?.try(&.as_s?),
            active: scene["active"]?.try(&.as_bool?) || false,
            hidden: scene["hidden"]?.try(&.as_bool?) || false
          )
        end
        inputs = data["audio_inputs"].as_a.map do |input|
          OBS::State::AudioState.new(
            name: input["name"].as_s,
            alias: input["alias"]?.try(&.as_s?),
            shortcut: input["shortcut"]?.try(&.as_s?),
            muted: input["muted"]?.try(&.as_bool?),
            volume_mul: OBS::Protocol::JsonValue.number(input["volume_mul"]?),
            volume_db: OBS::Protocol::JsonValue.number(input["volume_db"]?),
            volume_percent: input["volume_percent"]?.try(&.as_i?).try(&.to_i32)
          )
        end
        output = data["output"]?
        stats = data["stats"]?.try do |value|
          value.raw.nil? ? nil : OBS::State::ObsStats.new(
            cpu_usage_percent: OBS::Protocol::JsonValue.number(value["cpu_usage_percent"]?) || 0.0,
            memory_usage_mb: OBS::Protocol::JsonValue.number(value["memory_usage_mb"]?) || 0.0,
            available_disk_space_mb: OBS::Protocol::JsonValue.number(value["available_disk_space_mb"]?) || 0.0,
            active_fps: OBS::Protocol::JsonValue.number(value["active_fps"]?) || 0.0,
            average_frame_render_time_ms: OBS::Protocol::JsonValue.number(value["average_frame_render_time_ms"]?) || 0.0,
            render_skipped_frames: value["render_skipped_frames"]?.try(&.as_i64?) || 0_i64,
            render_total_frames: value["render_total_frames"]?.try(&.as_i64?) || 0_i64,
            output_skipped_frames: value["output_skipped_frames"]?.try(&.as_i64?) || 0_i64,
            output_total_frames: value["output_total_frames"]?.try(&.as_i64?) || 0_i64
          )
        end
        OBS::State::ObsSnapshot.new(
          connected: data["connected"].as_bool,
          obs_studio_version: data["obs_studio_version"]?.try(&.as_s?),
          obs_websocket_version: data["obs_websocket_version"]?.try(&.as_s?),
          current_scene: data["current_scene"]?.try(&.as_s?),
          scenes: scenes,
          audio_inputs: inputs,
          output: OBS::State::OutputState.new(
            streaming: output.try(&.["streaming"]?).try(&.as_bool?),
            recording: output.try(&.["recording"]?).try(&.as_bool?)
          ),
          profiles: string_array(data["profiles"]?),
          current_profile: data["current_profile"]?.try(&.as_s?),
          scene_collections: string_array(data["scene_collections"]?),
          current_scene_collection: data["current_scene_collection"]?.try(&.as_s?),
          stats: stats,
          stream_bitrate_kbps: OBS::Protocol::JsonValue.number(data["stream_bitrate_kbps"]?),
          stream_duration_ms: data["stream_duration_ms"]?.try(&.as_i64?),
          record_duration_ms: data["record_duration_ms"]?.try(&.as_i64?),
          last_error: data["last_error"]?.try(&.as_s?),
          updated_at: data["updated_at"]?.try(&.as_s?).try { |value| Time.parse_rfc3339(value) } || Time.utc
        )
      rescue TypeCastError | KeyError | Time::Format::Error
        nil
      end

      def self.string_array(data : JSON::Any?) : Array(String)
        data.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      end
    end
  end
end
