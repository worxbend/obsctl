require "../obs/protocol/event"
require "../obs/state/obs_snapshot"

module Obsctl
  module TUI
    # Applies server-pushed OBS events to an existing TUI snapshot.
    module EventApplier
      # Returns an updated snapshot for supported event types, otherwise the
      # original snapshot.
      def self.apply(snapshot : OBS::State::ObsSnapshot, event : OBS::Protocol::Event) : OBS::State::ObsSnapshot
        case event.event_type
        when "CurrentProgramSceneChanged"
          apply_scene_changed(snapshot, event)
        when "InputMuteStateChanged"
          apply_input_mute_changed(snapshot, event)
        when "InputVolumeChanged"
          apply_input_volume_changed(snapshot, event)
        else
          snapshot
        end
      end

      private def self.apply_scene_changed(snapshot : OBS::State::ObsSnapshot, event : OBS::Protocol::Event) : OBS::State::ObsSnapshot
        scene_name = event.event_data.try(&.["sceneName"].as_s?)
        return snapshot unless scene_name

        scenes = snapshot.scenes.map do |scene|
          OBS::State::SceneState.new(
            name: scene.name,
            alias: scene.alias,
            shortcut: scene.shortcut,
            group: scene.group,
            active: scene.name == scene_name
          )
        end
        replace_snapshot(snapshot, current_scene: scene_name, scenes: scenes)
      end

      private def self.apply_input_mute_changed(snapshot : OBS::State::ObsSnapshot, event : OBS::Protocol::Event) : OBS::State::ObsSnapshot
        data = event.event_data
        input_name = data.try(&.["inputName"].as_s?)
        muted = data.try(&.["inputMuted"].as_bool?)
        return snapshot unless input_name && !muted.nil?

        audio = snapshot.audio_inputs.map do |input|
          next input unless input.name == input_name

          OBS::State::AudioState.new(
            name: input.name,
            alias: input.alias,
            shortcut: input.shortcut,
            muted: muted,
            volume_mul: input.volume_mul,
            volume_db: input.volume_db,
            volume_percent: input.volume_percent
          )
        end
        replace_snapshot(snapshot, audio_inputs: audio)
      end

      private def self.apply_input_volume_changed(snapshot : OBS::State::ObsSnapshot, event : OBS::Protocol::Event) : OBS::State::ObsSnapshot
        data = event.event_data
        input_name = data.try(&.["inputName"].as_s?)
        volume_mul = number(data, "inputVolumeMul")
        volume_db = number(data, "inputVolumeDb")
        return snapshot unless input_name

        audio = snapshot.audio_inputs.map do |input|
          next input unless input.name == input_name

          resolved_mul = volume_mul.nil? ? input.volume_mul : volume_mul
          resolved_db = volume_db.nil? ? input.volume_db : volume_db
          percent = resolved_mul.try { |value| (value * 100).round.to_i32.clamp(0, 100) }
          OBS::State::AudioState.new(
            name: input.name,
            alias: input.alias,
            shortcut: input.shortcut,
            muted: input.muted,
            volume_mul: resolved_mul,
            volume_db: resolved_db,
            volume_percent: percent
          )
        end
        replace_snapshot(snapshot, audio_inputs: audio)
      end

      private def self.replace_snapshot(
        snapshot : OBS::State::ObsSnapshot,
        current_scene : String? = snapshot.current_scene,
        scenes : Array(OBS::State::SceneState) = snapshot.scenes,
        audio_inputs : Array(OBS::State::AudioState) = snapshot.audio_inputs,
      ) : OBS::State::ObsSnapshot
        OBS::State::ObsSnapshot.new(
          connected: snapshot.connected,
          obs_studio_version: snapshot.obs_studio_version,
          obs_websocket_version: snapshot.obs_websocket_version,
          current_scene: current_scene,
          scenes: scenes,
          audio_inputs: audio_inputs,
          output: snapshot.output,
          last_error: snapshot.last_error,
          updated_at: Time.utc
        )
      end

      private def self.number(data : JSON::Any?, key : String) : Float64?
        value = data.try(&.[key]?)
        return nil unless value
        value.as_f? || value.as_i?.try(&.to_f64)
      end
    end
  end
end
