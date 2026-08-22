require "json"
require "../obs/state/obs_snapshot"
require "../obs/state/scene_state"
require "../obs/state/audio_state"
require "../domain/volume"
require "../ipc/state_snapshot_codec"

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

      # Updates the current program scene without a full snapshot refetch.
      def update_current_scene(scene_name : String) : Nil
        mutate_connected do |current|
          scenes = current.scenes.map { |scene| scene.copy_with(active: scene.name == scene_name) }
          current.copy_with(current_scene: scene_name, scenes: scenes)
        end
      end

      # Updates one audio input's mute state without a full snapshot refetch.
      def update_input_mute(input_name : String, muted : Bool) : Nil
        mutate_connected do |current|
          current.copy_with(audio_inputs: map_input(current, input_name, &.copy_with(muted: muted)))
        end
      end

      # Updates one audio input's volume without a full snapshot refetch.
      def update_input_volume(input_name : String, volume_mul : Float64?, volume_db : Float64?) : Nil
        percent = volume_mul.try { |mul| Domain::Volume.mul_to_percent(mul) }
        mutate_connected do |current|
          inputs = map_input(current, input_name, &.copy_with(
            volume_mul: volume_mul, volume_db: volume_db, volume_percent: percent
          ))
          current.copy_with(audio_inputs: inputs)
        end
      end

      # Replaces the scene list in the cached snapshot and publishes.
      def update_scenes(current_scene : String?, scenes : Array(OBS::State::SceneState)) : Nil
        mutate_connected(&.copy_with(current_scene: current_scene, scenes: scenes))
      end

      # Replaces the audio input list in the cached snapshot and publishes.
      def update_audio_inputs(audio_inputs : Array(OBS::State::AudioState)) : Nil
        mutate_connected(&.copy_with(audio_inputs: audio_inputs))
      end

      def update_output(streaming : Bool? = nil, recording : Bool? = nil) : Nil
        mutate_connected do |current|
          current.copy_with(output: merged_output(current, streaming, recording))
        end
      end

      # Updates periodically polled performance and output telemetry while
      # preserving authoritative scene, audio, and profile state.
      #
      # `streaming`/`recording` are the poll's view of output state. They are
      # accepted here so a stream or recording toggled outside obsctl converges
      # even if its `StreamStateChanged` event never arrives; nil leaves the
      # cached value alone.
      def update_stats(
        stats : OBS::State::ObsStats,
        stream_bitrate_kbps : Float64?,
        stream_duration_ms : Int64?,
        record_duration_ms : Int64?,
        streaming : Bool? = nil,
        recording : Bool? = nil,
      ) : Nil
        mutate_connected do |current|
          current.copy_with(
            stats: stats,
            output: merged_output(current, streaming, recording),
            stream_bitrate_kbps: stream_bitrate_kbps,
            stream_duration_ms: stream_duration_ms,
            record_duration_ms: record_duration_ms
          )
        end
      end

      # Applies an incremental edit to the cached snapshot and publishes it.
      #
      # The block receives the current snapshot under the lock and returns the
      # replacement; `updated_at` is stamped here so no caller has to remember
      # it. A snapshot taken while OBS is disconnected is not authoritative —
      # the lists in it are whatever OBS last reported — so an edit against a
      # disconnected store is dropped rather than applied to stale data.
      #
      # The publish deliberately happens after the lock is released. Subscriber
      # fanout takes `ClientRegistry`'s lock, and that registry may in turn read
      # this store while holding it (see `ClientRegistry#add`, which sends the
      # initial snapshot during registration). Publishing from inside
      # `@lock.synchronize` would let those two locks be taken in both orders,
      # which is a deadlock. Keeping the publish out here is what makes the
      # order store-then-registry, always — and having exactly one place that
      # does it is what keeps it that way.
      private def mutate_connected(&) : Nil
        next_snapshot = @lock.synchronize do
          current = @snapshot
          next unless current.connected

          updated = (yield current).copy_with(updated_at: Time.utc)
          @snapshot = updated
          updated
        end
        publish_snapshot(next_snapshot) if next_snapshot
      end

      # Replaces one named audio input, leaving the rest of the list untouched.
      private def map_input(
        snapshot : OBS::State::ObsSnapshot,
        input_name : String,
        &block : OBS::State::AudioState -> OBS::State::AudioState
      ) : Array(OBS::State::AudioState)
        snapshot.audio_inputs.map do |input|
          input.name == input_name ? block.call(input) : input
        end
      end

      # Output state with nil meaning "leave whatever is cached alone".
      private def merged_output(
        snapshot : OBS::State::ObsSnapshot,
        streaming : Bool?,
        recording : Bool?,
      ) : OBS::State::OutputState
        OBS::State::OutputState.new(
          streaming: streaming.nil? ? snapshot.output.streaming : streaming,
          recording: recording.nil? ? snapshot.output.recording : recording
        )
      end

      # Records that the supervisor is attempting to establish an OBS session.
      def mark_reconnect_attempt(at : Time = Time.utc) : Nil
        @lock.synchronize do
          @telemetry = @telemetry.copy_with(reconnecting: true, last_reconnect_attempt_at: at)
        end
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
          @telemetry = @telemetry.copy_with(reconnecting: false, last_connected_at: at)
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
        next_snapshot = @lock.synchronize do
          current = @snapshot
          updated = current.copy_with(connected: false, last_error: error, updated_at: at)
          was_connected = current.connected
          @telemetry = @telemetry.copy_with(
            reconnecting: reconnecting,
            last_disconnected_at: was_connected ? at : @telemetry.last_disconnected_at,
            last_connection_failed_at: was_connected || !connection_failed ? @telemetry.last_connection_failed_at : at
          )
          @snapshot = updated
          updated
        end
        snapshot_to_json(next_snapshot)
      end

      # Returns the latest snapshot as the IPC state-event JSON payload.
      def snapshot_json : JSON::Any
        snapshot_to_json(snapshot)
      end

      # Converts a snapshot into the stable IPC state-event JSON shape.
      #
      # The shape itself belongs to `IPC::StateSnapshotCodec`, which owns both
      # this direction and the dashboard's decode of it.
      def self.snapshot_to_json(snapshot : OBS::State::ObsSnapshot) : JSON::Any
        IPC::StateSnapshotCodec.encode(snapshot)
      end

      private def snapshot_to_json(snapshot : OBS::State::ObsSnapshot) : JSON::Any
        self.class.snapshot_to_json(snapshot)
      end

      private def telemetry_for_snapshot_transition(
        current : OBS::State::ObsSnapshot,
        snapshot : OBS::State::ObsSnapshot,
      ) : ServerTelemetry
        if snapshot.connected
          return @telemetry if current.connected && !@telemetry.last_connected_at.nil? && !@telemetry.reconnecting

          @telemetry.copy_with(reconnecting: false, last_connected_at: Time.utc)
        elsif current.connected && !snapshot.connected
          @telemetry.copy_with(last_disconnected_at: Time.utc)
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
