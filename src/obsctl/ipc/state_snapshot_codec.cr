require "json"
require "../json_value"
require "../state/obs_snapshot"
require "../state/scene_state"
require "../state/audio_state"
require "../state/output_state"
require "../state/obs_stats"

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
      def self.encode(snapshot : State::ObsSnapshot) : JSON::Any
        JSON::Any.new({
          "connected"                => json_any(snapshot.connected),
          "obs_studio_version"       => json_any(snapshot.obs_studio_version),
          "obs_websocket_version"    => json_any(snapshot.obs_websocket_version),
          "current_scene"            => json_any(snapshot.current_scene),
          "scenes"                   => json_any(snapshot.scenes.map { |scene| encode_scene(scene) }),
          "audio_inputs"             => json_any(snapshot.audio_inputs.map { |input| encode_audio_input(input) }),
          "output"                   => encode_output(snapshot.output),
          "profiles"                 => json_any(snapshot.profiles),
          "current_profile"          => json_any(snapshot.current_profile),
          "scene_collections"        => json_any(snapshot.scene_collections),
          "current_scene_collection" => json_any(snapshot.current_scene_collection),
          "scene_profiles"           => json_any(snapshot.scene_profiles.map { |profile| encode_scene_profile(profile) }),
          "active_scene_profile"     => json_any(snapshot.active_scene_profile),
          "stats"                    => encode_stats(snapshot.stats),
          "stream_bitrate_kbps"      => json_any(snapshot.stream_bitrate_kbps),
          "stream_duration_ms"       => json_any(snapshot.stream_duration_ms),
          "record_duration_ms"       => json_any(snapshot.record_duration_ms),
          "last_error"               => json_any(snapshot.last_error),
          "updated_at"               => json_any(snapshot.updated_at.to_rfc3339),
        } of String => JSON::Any)
      end

      private def self.encode_stats(stats : State::ObsStats?) : JSON::Any
        return json_any(nil) unless stats

        JSON::Any.new({
          "cpu_usage_percent"            => json_any(stats.cpu_usage_percent),
          "memory_usage_mb"              => json_any(stats.memory_usage_mb),
          "available_disk_space_mb"      => json_any(stats.available_disk_space_mb),
          "active_fps"                   => json_any(stats.active_fps),
          "average_frame_render_time_ms" => json_any(stats.average_frame_render_time_ms),
          "render_skipped_frames"        => json_any(stats.render_skipped_frames),
          "render_total_frames"          => json_any(stats.render_total_frames),
          "output_skipped_frames"        => json_any(stats.output_skipped_frames),
          "output_total_frames"          => json_any(stats.output_total_frames),
        } of String => JSON::Any)
      end

      private def self.encode_scene(scene : State::SceneState) : JSON::Any
        JSON::Any.new({
          "name"     => json_any(scene.name),
          "alias"    => json_any(scene.alias),
          "shortcut" => json_any(scene.shortcut),
          "group"    => json_any(scene.group),
          "active"   => json_any(scene.active),
          "hidden"   => json_any(scene.hidden),
        } of String => JSON::Any)
      end

      private def self.encode_audio_input(input : State::AudioState) : JSON::Any
        JSON::Any.new({
          "name"           => json_any(input.name),
          "alias"          => json_any(input.alias),
          "shortcut"       => json_any(input.shortcut),
          "muted"          => json_any(input.muted),
          "volume_mul"     => json_any(input.volume_mul),
          "volume_db"      => json_any(input.volume_db),
          "volume_percent" => json_any(input.volume_percent),
        } of String => JSON::Any)
      end

      private def self.encode_output(output : State::OutputState) : JSON::Any
        JSON::Any.new({
          "streaming" => json_any(output.streaming),
          "recording" => json_any(output.recording),
        } of String => JSON::Any)
      end

      private def self.encode_scene_profile(profile : State::SceneProfileState) : JSON::Any
        JSON::Any.new({
          "name"   => json_any(profile.name),
          "hidden" => json_any(profile.hidden),
        } of String => JSON::Any)
      end

      def self.decode(data : JSON::Any) : State::ObsSnapshot?
        State::ObsSnapshot.new(
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
          stream_bitrate_kbps: JsonValue.number(data["stream_bitrate_kbps"]?),
          stream_duration_ms: int64_field(data, "stream_duration_ms"),
          record_duration_ms: int64_field(data, "record_duration_ms"),
          last_error: string_field(data, "last_error"),
          updated_at: parsed_time(string_field(data, "updated_at"))
        )
      rescue TypeCastError | KeyError | Time::Format::Error
        nil
      end

      private def self.decode_scenes(data : JSON::Any) : Array(State::SceneState)
        data.as_a.map { |scene| decode_scene(scene) }
      end

      private def self.decode_scene(scene : JSON::Any) : State::SceneState
        State::SceneState.new(
          name: scene["name"].as_s,
          alias: string_field(scene, "alias"),
          shortcut: string_field(scene, "shortcut"),
          group: string_field(scene, "group"),
          active: bool_field(scene, "active") || false,
          hidden: bool_field(scene, "hidden") || false
        )
      end

      private def self.decode_audio_inputs(data : JSON::Any) : Array(State::AudioState)
        data.as_a.map { |input| decode_audio_input(input) }
      end

      private def self.decode_audio_input(input : JSON::Any) : State::AudioState
        State::AudioState.new(
          name: input["name"].as_s,
          alias: string_field(input, "alias"),
          shortcut: string_field(input, "shortcut"),
          muted: bool_field(input, "muted"),
          volume_mul: JsonValue.number(input["volume_mul"]?),
          volume_db: JsonValue.number(input["volume_db"]?),
          volume_percent: int_field(input, "volume_percent")
        )
      end

      private def self.decode_output(data : JSON::Any?) : State::OutputState
        State::OutputState.new(
          streaming: data.try { |value| bool_field(value, "streaming") },
          recording: data.try { |value| bool_field(value, "recording") }
        )
      end

      private def self.decode_stats(data : JSON::Any?) : State::ObsStats?
        return unless data
        return if data.raw.nil?

        State::ObsStats.new(
          cpu_usage_percent: JsonValue.number(data["cpu_usage_percent"]?) || 0.0,
          memory_usage_mb: JsonValue.number(data["memory_usage_mb"]?) || 0.0,
          available_disk_space_mb: JsonValue.number(data["available_disk_space_mb"]?) || 0.0,
          active_fps: JsonValue.number(data["active_fps"]?) || 0.0,
          average_frame_render_time_ms: JsonValue.number(data["average_frame_render_time_ms"]?) || 0.0,
          render_skipped_frames: int64_field(data, "render_skipped_frames") || 0_i64,
          render_total_frames: int64_field(data, "render_total_frames") || 0_i64,
          output_skipped_frames: int64_field(data, "output_skipped_frames") || 0_i64,
          output_total_frames: int64_field(data, "output_total_frames") || 0_i64
        )
      end

      def self.scene_profiles(data : JSON::Any?) : Array(State::SceneProfileState)
        entries = data.try(&.as_a?)
        return [] of State::SceneProfileState unless entries

        entries.compact_map do |entry|
          name = entry["name"]?.try(&.as_s?)
          next unless name

          State::SceneProfileState.new(name, string_array(entry["hidden"]?))
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

      private def self.json_any(value : (Bool | Float64 | Int32 | Int64 | String)?) : JSON::Any
        JSON::Any.new(value)
      end

      private def self.json_any(value : Array(String)) : JSON::Any
        JSON::Any.new(value.map { |entry| JSON::Any.new(entry) })
      end

      private def self.json_any(value : Array(JSON::Any)) : JSON::Any
        JSON::Any.new(value)
      end
    end
  end
end
