require "../../spec_helper"
require "../../../src/obsctl/server/state_store"

private def obs_snapshot(
  connected : Bool = true,
  current_scene : String? = "Main Camera",
  last_error : String? = nil,
  updated_at : Time = Time.utc,
) : Obsctl::OBS::State::ObsSnapshot
  Obsctl::OBS::State::ObsSnapshot.new(
    connected: connected,
    obs_studio_version: connected ? "30.1.0" : nil,
    obs_websocket_version: connected ? "5.3.0" : nil,
    current_scene: current_scene,
    scenes: [
      Obsctl::OBS::State::SceneState.new("Main Camera", active: current_scene == "Main Camera"),
      Obsctl::OBS::State::SceneState.new("BRB", active: current_scene == "BRB"),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new("Mic/Aux", muted: false, volume_percent: 70),
    ],
    last_error: last_error,
    updated_at: updated_at
  )
end

describe Obsctl::Server::StateStore do
  it "records startup failure as a failed connection attempt only" do
    state = Obsctl::Server::StateStore.new
    failed_at = Time.utc(2026, 6, 20, 12, 0, 0)

    state.mark_disconnected("OBS unavailable", reconnecting: false, at: failed_at)

    telemetry = state.telemetry
    telemetry.reconnecting.should be_false
    telemetry.last_connected_at.should be_nil
    telemetry.last_disconnected_at.should be_nil
    telemetry.last_reconnect_attempt_at.should be_nil
    telemetry.last_connection_failed_at.should eq(failed_at)
    state.snapshot.last_error.should eq("OBS unavailable")
  end

  it "records passive disconnect after a successful session without changing failed-at history" do
    state = Obsctl::Server::StateStore.new
    failed_at = Time.utc(2026, 6, 20, 12, 0, 0)
    connected_at = Time.utc(2026, 6, 20, 12, 1, 0)
    disconnected_at = Time.utc(2026, 6, 20, 12, 2, 0)

    state.mark_disconnected("startup failed", at: failed_at)
    state.mark_connected(obs_snapshot(updated_at: connected_at), at: connected_at)
    state.mark_disconnected("OBS WebSocket disconnected", reconnecting: true, at: disconnected_at)

    telemetry = state.telemetry
    telemetry.reconnecting.should be_true
    telemetry.last_connected_at.should eq(connected_at)
    telemetry.last_disconnected_at.should eq(disconnected_at)
    telemetry.last_connection_failed_at.should eq(failed_at)
    state.snapshot.connected.should be_false
    state.snapshot.last_error.should eq("OBS WebSocket disconnected")
  end

  it "records failed reconnect after prior success as the newest failed attempt" do
    state = Obsctl::Server::StateStore.new
    connected_at = Time.utc(2026, 6, 20, 12, 0, 0)
    disconnected_at = Time.utc(2026, 6, 20, 12, 1, 0)
    attempt_at = Time.utc(2026, 6, 20, 12, 2, 0)
    failed_at = Time.utc(2026, 6, 20, 12, 2, 5)

    state.mark_connected(obs_snapshot(updated_at: connected_at), at: connected_at)
    state.mark_disconnected("OBS WebSocket disconnected", reconnecting: true, at: disconnected_at)
    state.mark_reconnect_attempt(attempt_at)
    state.mark_disconnected("OBS unavailable", reconnecting: true, at: failed_at)

    telemetry = state.telemetry
    telemetry.reconnecting.should be_true
    telemetry.last_connected_at.should eq(connected_at)
    telemetry.last_disconnected_at.should eq(disconnected_at)
    telemetry.last_reconnect_attempt_at.should eq(attempt_at)
    telemetry.last_connection_failed_at.should eq(failed_at)
    state.snapshot.last_error.should eq("OBS unavailable")
  end

  it "keeps explicit reconnect requested only until the next failure outcome" do
    state = Obsctl::Server::StateStore.new
    connected_at = Time.utc(2026, 6, 20, 12, 0, 0)
    requested_at = Time.utc(2026, 6, 20, 12, 1, 0)
    failed_at = Time.utc(2026, 6, 20, 12, 2, 0)

    state.mark_connected(obs_snapshot(updated_at: connected_at), at: connected_at)
    state.mark_disconnected(
      "OBS reconnect requested",
      reconnecting: true,
      at: requested_at,
      connection_failed: false
    )

    requested = state.telemetry
    requested.reconnecting.should be_true
    requested.last_disconnected_at.should eq(requested_at)
    requested.last_connection_failed_at.should be_nil
    state.snapshot.last_error.should eq("OBS reconnect requested")

    state.mark_disconnected("OBS unavailable", reconnecting: true, at: failed_at)

    failed = state.telemetry
    failed.last_disconnected_at.should eq(requested_at)
    failed.last_connection_failed_at.should eq(failed_at)
    state.snapshot.last_error.should eq("OBS unavailable")
  end

  it "keeps explicit reconnect requested only until the next successful outcome" do
    state = Obsctl::Server::StateStore.new
    connected_at = Time.utc(2026, 6, 20, 12, 0, 0)
    requested_at = Time.utc(2026, 6, 20, 12, 1, 0)
    reconnected_at = Time.utc(2026, 6, 20, 12, 2, 0)

    state.mark_connected(obs_snapshot(updated_at: connected_at), at: connected_at)
    state.mark_disconnected(
      "OBS reconnect requested",
      reconnecting: true,
      at: requested_at,
      connection_failed: false
    )
    state.snapshot.last_error.should eq("OBS reconnect requested")

    state.mark_connected(obs_snapshot(current_scene: "BRB", updated_at: reconnected_at), at: reconnected_at)

    telemetry = state.telemetry
    telemetry.reconnecting.should be_false
    telemetry.last_connected_at.should eq(reconnected_at)
    telemetry.last_disconnected_at.should eq(requested_at)
    telemetry.last_connection_failed_at.should be_nil
    state.snapshot.connected.should be_true
    state.snapshot.current_scene.should eq("BRB")
    state.snapshot.last_error.should be_nil
  end

  it "preserves the most recent failed attempt across successful reconnects" do
    state = Obsctl::Server::StateStore.new
    failed_at = Time.utc(2026, 6, 20, 12, 0, 0)
    connected_at = Time.utc(2026, 6, 20, 12, 1, 0)
    requested_at = Time.utc(2026, 6, 20, 12, 1, 30)
    second_failure_at = Time.utc(2026, 6, 20, 12, 2, 0)
    reconnected_at = Time.utc(2026, 6, 20, 12, 3, 0)

    state.mark_disconnected("startup failed", at: failed_at)
    state.mark_connected(obs_snapshot(updated_at: connected_at), at: connected_at)

    telemetry_after_success = state.telemetry
    telemetry_after_success.last_connected_at.should eq(connected_at)
    telemetry_after_success.last_connection_failed_at.should eq(failed_at)

    state.mark_disconnected(
      "OBS reconnect requested",
      reconnecting: true,
      at: requested_at,
      connection_failed: false
    )
    state.mark_disconnected("OBS unavailable", reconnecting: true, at: second_failure_at)
    state.mark_connected(obs_snapshot(current_scene: "BRB", updated_at: reconnected_at), at: reconnected_at)

    telemetry_after_reconnect = state.telemetry
    telemetry_after_reconnect.last_connected_at.should eq(reconnected_at)
    telemetry_after_reconnect.last_disconnected_at.should eq(requested_at)
    telemetry_after_reconnect.last_connection_failed_at.should eq(second_failure_at)
    state.snapshot.connected.should be_true
    state.snapshot.last_error.should be_nil
  end
end
