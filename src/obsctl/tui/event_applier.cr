require "json"
require "../ipc/event"
require "./model"

module Obsctl
  module TUI
    module EventApplier
      extend self

      # Applies a server-pushed event. False means the high-frequency meter
      # update can wait for the regular render tick; true requests a redraw.
      def apply(model : Model, event : IPC::Event) : Bool
        data = event.data
        return true unless data
        case event.topic
        when "state"
          snapshot = parse_snapshot(data)
          return true unless snapshot
          previous_scene = model.current_scene
          current_scene = snapshot.current_scene
          if previous_scene && current_scene && previous_scene != current_scene
            model.scene_flash = {current_scene, model.anim.frame}
          end
          model.snapshot = snapshot
          model.connected_to_daemon = true
          model.record_metric_sample
          model.clamp_cursors
          true
        when "logs"
          if log = parse_log(data)
            model.push_log(log)
          end
          true
        when "events"
          apply_obs_event(model, data)
        else
          true
        end
      rescue TypeCastError | KeyError | Time::Format::Error
        true
      end

      private def parse_snapshot(data : JSON::Any) : OBS::State::ObsSnapshot?
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
            volume_mul: number(input["volume_mul"]?),
            volume_db: number(input["volume_db"]?),
            volume_percent: input["volume_percent"]?.try(&.as_i?).try(&.to_i32)
          )
        end
        output = data["output"]?
        stats = data["stats"]?.try do |value|
          value.raw.nil? ? nil : OBS::State::ObsStats.new(
            cpu_usage_percent: number(value["cpu_usage_percent"]?) || 0.0,
            memory_usage_mb: number(value["memory_usage_mb"]?) || 0.0,
            available_disk_space_mb: number(value["available_disk_space_mb"]?) || 0.0,
            active_fps: number(value["active_fps"]?) || 0.0,
            average_frame_render_time_ms: number(value["average_frame_render_time_ms"]?) || 0.0,
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
          stream_bitrate_kbps: number(data["stream_bitrate_kbps"]?),
          stream_duration_ms: data["stream_duration_ms"]?.try(&.as_i64?),
          record_duration_ms: data["record_duration_ms"]?.try(&.as_i64?),
          last_error: data["last_error"]?.try(&.as_s?),
          updated_at: data["updated_at"]?.try(&.as_s?).try { |value| Time.parse_rfc3339(value) } || Time.utc
        )
      rescue TypeCastError | KeyError | Time::Format::Error
        nil
      end

      private def parse_log(data : JSON::Any) : LogEntry?
        message = data["message"]?.try(&.as_s?)
        return unless message
        level = case data["level"]?.try(&.as_s?).try(&.downcase)
                when "debug"           then Runtime::LogLevel::Debug
                when "warn", "warning" then Runtime::LogLevel::Warn
                when "error"           then Runtime::LogLevel::Error
                else                        Runtime::LogLevel::Info
                end
        timestamp = (data["created_at"]? || data["timestamp"]?).try(&.as_s?).try { |value| Time.parse_rfc3339(value) } || Time.utc
        LogEntry.new(level, message, data["code"]?.try(&.as_s?), timestamp)
      rescue Time::Format::Error
        nil
      end

      private def apply_obs_event(model : Model, data : JSON::Any) : Bool
        event_type = data["type"]?.try(&.as_s?) || data["event_type"]?.try(&.as_s?)
        return true unless event_type == "InputVolumeMeters"
        payload = data["event_data"]? || data
        inputs = payload["inputs"]?.try(&.as_a?) || [] of JSON::Any
        inputs.each do |input|
          name = input["name"]?.try(&.as_s?) || input["inputName"]?.try(&.as_s?)
          level = number(input["level"]?) || meter_level(input["inputLevelsMul"]?)
          model.record_meter_level(name, level) if name && level
        end
        false
      end

      # obs-websocket sends one [magnitude, peak, input peak] tuple per
      # channel. Match the Rust adapter by displaying the loudest channel.
      private def meter_level(data : JSON::Any?) : Float64?
        channels = data.try(&.as_a?)
        return unless channels
        channels.reduce(0.0) do |maximum, channel|
          magnitude = channel.as_a?.try(&.first?).try { |value| number(value) }
          return unless magnitude && magnitude.finite? && magnitude >= 0.0
          Math.max(maximum, magnitude)
        end
      end

      private def string_array(data : JSON::Any?) : Array(String)
        data.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      end

      private def number(data : JSON::Any?) : Float64?
        data.try { |value| value.as_f? || value.as_i?.try(&.to_f64) }
      end
    end
  end
end
