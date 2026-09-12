require "json"
require "../ipc/event"
require "../obs/protocol/json_value"
require "../ipc/state_snapshot_codec"
require "./model"

module Obsctl
  module TUI
    module EventApplier
      extend self

      # Applies a server-pushed event. False means the high-frequency meter
      # update can wait for the regular render tick; true requests a redraw.
      def apply(model : Model, event : IPC::Event) : Bool
        data = event.data
        return false unless data
        case event.topic
        when "state"  then apply_state(model, data)
        when "logs"   then apply_log(model, data)
        when "events" then apply_obs_event(model, data)
        else               false
        end
      rescue TypeCastError | KeyError | Time::Format::Error
        false
      end

      private def parse_snapshot(data : JSON::Any) : OBS::State::ObsSnapshot?
        IPC::StateSnapshotCodec.decode(data)
      end

      private def apply_state(model : Model, data : JSON::Any) : Bool
        snapshot = parse_snapshot(data)
        return false unless snapshot

        flash_scene_change(model, snapshot.current_scene)
        model.snapshot = snapshot
        model.connected_to_daemon = true
        model.record_metric_sample
        model.clamp_cursors
        true
      end

      private def flash_scene_change(model : Model, current_scene : String?) : Nil
        previous_scene = model.current_scene
        return unless previous_scene && current_scene && previous_scene != current_scene

        model.scene_flash = {current_scene, model.anim.frame}
      end

      private def apply_log(model : Model, data : JSON::Any) : Bool
        return false unless log = parse_log(data)

        model.push_log(log)
        true
      end

      private def parse_log(data : JSON::Any) : LogEntry?
        message = data["message"]?.try(&.as_s?)
        return unless message

        LogEntry.new(log_level(data), message, data["code"]?.try(&.as_s?), log_timestamp(data))
      rescue Time::Format::Error
        nil
      end

      private def log_level(data : JSON::Any) : Runtime::LogLevel
        case data["level"]?.try(&.as_s?).try(&.downcase)
        when "debug"           then Runtime::LogLevel::Debug
        when "warn", "warning" then Runtime::LogLevel::Warn
        when "error"           then Runtime::LogLevel::Error
        else                        Runtime::LogLevel::Info
        end
      end

      private def log_timestamp(data : JSON::Any) : Time
        (data["created_at"]? || data["timestamp"]?).try(&.as_s?).try { |value| Time.parse_rfc3339(value) } || Time.utc
      end

      private def apply_obs_event(model : Model, data : JSON::Any) : Bool
        return false unless meter_event?(data)

        meter_inputs(data).each do |input|
          if reading = meter_reading(input)
            model.record_meter_level(reading[0], reading[1])
          end
        end
        false
      end

      private def meter_event?(data : JSON::Any) : Bool
        (data["type"]?.try(&.as_s?) || data["event_type"]?.try(&.as_s?)) == "InputVolumeMeters"
      end

      private def meter_inputs(data : JSON::Any) : Array(JSON::Any)
        (data["event_data"]? || data)["inputs"]?.try(&.as_a?) || [] of JSON::Any
      end

      private def meter_reading(data : JSON::Any) : Tuple(String, Float64)?
        name = data["name"]?.try(&.as_s?) || data["inputName"]?.try(&.as_s?)
        level = OBS::Protocol::JsonValue.number(data["level"]?) || meter_level(data["inputLevelsMul"]?)
        return unless name && level

        {name, level}
      end

      # obs-websocket sends one [magnitude, peak, input peak] tuple per
      # channel. Match the Rust adapter by displaying the loudest channel.
      private def meter_level(data : JSON::Any?) : Float64?
        channels = data.try(&.as_a?)
        return unless channels
        channels.reduce(0.0) do |maximum, channel|
          magnitude = channel.as_a?.try(&.first?).try { |value| OBS::Protocol::JsonValue.number(value) }
          return unless magnitude && magnitude.finite? && magnitude >= 0.0
          Math.max(maximum, magnitude)
        end
      end
    end
  end
end
