require "json"
require "../obs/state/obs_snapshot"
require "../obs/state/scene_state"
require "../obs/state/audio_state"

module Obsctl
  module Server
    class StateStore
      def initialize(@on_update : Proc(JSON::Any, Nil)? = nil)
        @snapshot = disconnected_snapshot
        @lock = Mutex.new
      end

      def snapshot : OBS::State::ObsSnapshot
        @lock.synchronize { @snapshot }
      end

      def update(snapshot : OBS::State::ObsSnapshot) : Nil
        @lock.synchronize { @snapshot = snapshot }
        publish_snapshot(snapshot)
      end

      def mark_disconnected(error : String? = nil) : Nil
        next_snapshot = nil
        @lock.synchronize do
          current = @snapshot
          next_snapshot = OBS::State::ObsSnapshot.new(
            connected: false,
            obs_studio_version: current.obs_studio_version,
            obs_websocket_version: current.obs_websocket_version,
            current_scene: current.current_scene,
            scenes: current.scenes,
            audio_inputs: current.audio_inputs,
            output: current.output,
            last_error: error,
            updated_at: Time.utc
          )
          @snapshot = next_snapshot.not_nil!
        end
        publish_snapshot(next_snapshot.not_nil!)
      end

      def snapshot_json : JSON::Any
        snapshot_to_json(snapshot)
      end

      def self.snapshot_to_json(snapshot : OBS::State::ObsSnapshot) : JSON::Any
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
          last_error: snapshot.last_error,
          updated_at: snapshot.updated_at.to_rfc3339,
        }.to_json)
      end

      private def snapshot_to_json(snapshot : OBS::State::ObsSnapshot) : JSON::Any
        self.class.snapshot_to_json(snapshot)
      end

      private def publish_snapshot(snapshot : OBS::State::ObsSnapshot) : Nil
        @on_update.try(&.call(snapshot_to_json(snapshot)))
      end

      private def disconnected_snapshot : OBS::State::ObsSnapshot
        OBS::State::ObsSnapshot.new(
          connected: false,
          obs_studio_version: nil,
          obs_websocket_version: nil,
          current_scene: nil,
          scenes: [] of OBS::State::SceneState,
          audio_inputs: [] of OBS::State::AudioState
        )
      end
    end
  end
end
