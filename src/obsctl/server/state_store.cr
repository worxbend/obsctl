require "json"
require "../obs/state/obs_snapshot"
require "../obs/state/scene_state"
require "../obs/state/audio_state"

module Obsctl
  module Server
    # Server-owned OBS connection telemetry exposed by daemon status.
    # `last_connection_failed_at` records the most recent failed OBS connection
    # attempt and is preserved across later successful connections.
    record ServerTelemetry,
      reconnecting : Bool = false,
      last_connected_at : Time? = nil,
      last_disconnected_at : Time? = nil,
      last_reconnect_attempt_at : Time? = nil,
      last_connection_failed_at : Time? = nil

    # Authoritative OBS snapshot cache owned by the local daemon.
    class StateStore
      # Creates a disconnected state store with an optional update callback.
      def initialize(@on_update : Proc(JSON::Any, Nil)? = nil)
        @snapshot = disconnected_snapshot
        @telemetry = ServerTelemetry.new
        @lock = Mutex.new
      end

      # Returns the latest cached OBS snapshot.
      def snapshot : OBS::State::ObsSnapshot
        @lock.synchronize { @snapshot }
      end

      # Returns the current daemon-side OBS connection telemetry.
      def telemetry : ServerTelemetry
        @lock.synchronize { @telemetry }
      end

      # Replaces the cached snapshot and publishes it to subscribers.
      def update(snapshot : OBS::State::ObsSnapshot) : Nil
        @lock.synchronize do
          @telemetry = telemetry_for_snapshot_transition(@snapshot, snapshot)
          @snapshot = snapshot
        end
        publish_snapshot(snapshot)
      end

      # Records that the supervisor is attempting to establish an OBS session.
      def mark_reconnect_attempt(at : Time = Time.utc) : Nil
        @lock.synchronize do
          @telemetry = ServerTelemetry.new(
            reconnecting: true,
            last_connected_at: @telemetry.last_connected_at,
            last_disconnected_at: @telemetry.last_disconnected_at,
            last_reconnect_attempt_at: at,
            last_connection_failed_at: @telemetry.last_connection_failed_at
          )
        end
      end

      # Records a public operator reconnect request without treating it as an
      # OBS connection failure.
      def mark_reconnect_requested(at : Time = Time.utc) : Nil
        publish_snapshot_payload(mark_reconnect_requested_and_build_payload(at))
      end

      # Mutates authoritative reconnect state for a public operator reconnect
      # request and returns the precomputed state-event payload so callers can
      # defer subscriber fanout until their own locks are released.
      def mark_reconnect_requested_and_build_payload(at : Time = Time.utc) : JSON::Any
        mark_disconnected_payload(
          "OBS reconnect requested",
          reconnecting: true,
          at: at,
          connection_failed: false
        )
      end

      # Records a successful OBS connection and publishes its fresh snapshot.
      def mark_connected(snapshot : OBS::State::ObsSnapshot, at : Time = Time.utc) : Nil
        @lock.synchronize do
          @telemetry = ServerTelemetry.new(
            reconnecting: false,
            last_connected_at: at,
            last_disconnected_at: @telemetry.last_disconnected_at,
            last_reconnect_attempt_at: @telemetry.last_reconnect_attempt_at,
            last_connection_failed_at: @telemetry.last_connection_failed_at
          )
          @snapshot = snapshot
        end
        publish_snapshot(snapshot)
      end

      # Marks OBS unavailable while preserving the last known lists and versions.
      def mark_disconnected(
        error : String? = nil,
        reconnecting : Bool = false,
        at : Time = Time.utc,
        connection_failed : Bool = true,
      ) : Nil
        publish_snapshot_payload(mark_disconnected_payload(error, reconnecting, at, connection_failed))
      end

      # Publishes a precomputed state-event payload to subscribers.
      def publish_snapshot_payload(payload : JSON::Any) : Nil
        @on_update.try(&.call(payload))
      end

      private def mark_disconnected_payload(
        error : String? = nil,
        reconnecting : Bool = false,
        at : Time = Time.utc,
        connection_failed : Bool = true,
      ) : JSON::Any
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
            updated_at: at
          )
          was_connected = current.connected
          @telemetry = ServerTelemetry.new(
            reconnecting: reconnecting,
            last_connected_at: @telemetry.last_connected_at,
            last_disconnected_at: was_connected ? at : @telemetry.last_disconnected_at,
            last_reconnect_attempt_at: @telemetry.last_reconnect_attempt_at,
            last_connection_failed_at: was_connected || !connection_failed ? @telemetry.last_connection_failed_at : at
          )
          @snapshot = next_snapshot.not_nil!
        end
        snapshot_to_json(next_snapshot.not_nil!)
      end

      # Returns the latest snapshot as the IPC state-event JSON payload.
      def snapshot_json : JSON::Any
        snapshot_to_json(snapshot)
      end

      # Converts a snapshot into the stable IPC state-event JSON shape.
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

      private def telemetry_for_snapshot_transition(
        current : OBS::State::ObsSnapshot,
        snapshot : OBS::State::ObsSnapshot,
      ) : ServerTelemetry
        if snapshot.connected
          return @telemetry unless !current.connected || @telemetry.last_connected_at.nil? || @telemetry.reconnecting

          ServerTelemetry.new(
            reconnecting: false,
            last_connected_at: Time.utc,
            last_disconnected_at: @telemetry.last_disconnected_at,
            last_reconnect_attempt_at: @telemetry.last_reconnect_attempt_at,
            last_connection_failed_at: @telemetry.last_connection_failed_at
          )
        elsif current.connected && !snapshot.connected
          ServerTelemetry.new(
            reconnecting: @telemetry.reconnecting,
            last_connected_at: @telemetry.last_connected_at,
            last_disconnected_at: Time.utc,
            last_reconnect_attempt_at: @telemetry.last_reconnect_attempt_at,
            last_connection_failed_at: @telemetry.last_connection_failed_at
          )
        else
          @telemetry
        end
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
