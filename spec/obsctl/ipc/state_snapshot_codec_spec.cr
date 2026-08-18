require "../../spec_helper"
require "../../../src/obsctl/ipc/state_snapshot_codec"

private def full_snapshot
  Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "30.1.2",
    obs_websocket_version: "5.4.2",
    current_scene: "Main Camera",
    scenes: [
      Obsctl::OBS::State::SceneState.new(
        name: "Main Camera", alias: "cam", shortcut: "1",
        group: "live", active: true, hidden: false),
      Obsctl::OBS::State::SceneState.new(name: "BRB", hidden: true),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new(
        name: "Mic", alias: "mic", shortcut: "m",
        muted: false, volume_mul: 0.75, volume_db: -2.5, volume_percent: 75),
      Obsctl::OBS::State::AudioState.new(name: "Desktop"),
    ],
    output: Obsctl::OBS::State::OutputState.new(streaming: true, recording: false),
    profiles: ["Default", "Streaming"],
    current_profile: "Streaming",
    scene_collections: ["Main"],
    current_scene_collection: "Main",
    stats: Obsctl::OBS::State::ObsStats.new(
      cpu_usage_percent: 12.5, memory_usage_mb: 2048.0,
      available_disk_space_mb: 51200.0, active_fps: 60.0,
      average_frame_render_time_ms: 1.25,
      render_skipped_frames: 3_i64, render_total_frames: 1000_i64,
      output_skipped_frames: 1_i64, output_total_frames: 900_i64),
    stream_bitrate_kbps: 6000.0,
    stream_duration_ms: 123_456_i64,
    record_duration_ms: 65_432_i64,
    last_error: nil,
    updated_at: Time.utc(2026, 8, 16, 12, 0, 0)
  )
end

# The daemon encodes, the dashboard decodes, and `docs/protocol.md` freezes the
# shape in between. Nothing but agreement between the two halves makes the TUI
# show what the daemon actually reported, so the round trip is the contract.
describe Obsctl::IPC::StateSnapshotCodec do
  it "round trips a fully populated snapshot" do
    original = full_snapshot
    decoded = Obsctl::IPC::StateSnapshotCodec.decode(
      Obsctl::IPC::StateSnapshotCodec.encode(original)
    )

    decoded.should_not be_nil
    decoded = decoded.not_nil!

    decoded.connected.should eq(original.connected)
    decoded.obs_studio_version.should eq(original.obs_studio_version)
    decoded.obs_websocket_version.should eq(original.obs_websocket_version)
    decoded.current_scene.should eq(original.current_scene)
    decoded.scenes.should eq(original.scenes)
    decoded.audio_inputs.should eq(original.audio_inputs)
    decoded.output.should eq(original.output)
    decoded.profiles.should eq(original.profiles)
    decoded.current_profile.should eq(original.current_profile)
    decoded.scene_collections.should eq(original.scene_collections)
    decoded.current_scene_collection.should eq(original.current_scene_collection)
    decoded.stats.should eq(original.stats)
    decoded.stream_bitrate_kbps.should eq(original.stream_bitrate_kbps)
    decoded.stream_duration_ms.should eq(original.stream_duration_ms)
    decoded.record_duration_ms.should eq(original.record_duration_ms)
    decoded.updated_at.to_rfc3339.should eq(original.updated_at.to_rfc3339)
  end

  it "round trips a disconnected snapshot with an error" do
    original = Obsctl::OBS::State::ObsSnapshot.new(
      connected: false,
      obs_studio_version: nil,
      obs_websocket_version: nil,
      current_scene: nil,
      scenes: [] of Obsctl::OBS::State::SceneState,
      audio_inputs: [] of Obsctl::OBS::State::AudioState,
      last_error: "OBS WebSocket disconnected"
    )
    decoded = Obsctl::IPC::StateSnapshotCodec.decode(
      Obsctl::IPC::StateSnapshotCodec.encode(original)
    ).not_nil!

    decoded.connected.should be_false
    decoded.last_error.should eq("OBS WebSocket disconnected")
    decoded.scenes.should be_empty
    decoded.audio_inputs.should be_empty
    decoded.stats.should be_nil
  end

  it "preserves the hidden and active scene flags the dashboard filters on" do
    decoded = Obsctl::IPC::StateSnapshotCodec.decode(
      Obsctl::IPC::StateSnapshotCodec.encode(full_snapshot)
    ).not_nil!

    decoded.scenes.first.active.should be_true
    decoded.scenes.last.hidden.should be_true
  end

  it "preserves an unmuted input distinctly from one whose state is unknown" do
    # `false` and `nil` render differently — "♪" versus "unknown" — so a codec
    # that collapsed them would silently claim an input was live.
    decoded = Obsctl::IPC::StateSnapshotCodec.decode(
      Obsctl::IPC::StateSnapshotCodec.encode(full_snapshot)
    ).not_nil!

    decoded.audio_inputs.first.muted.should be_false
    decoded.audio_inputs.last.muted.should be_nil
  end

  it "returns nil for a payload that is not a state snapshot" do
    Obsctl::IPC::StateSnapshotCodec.decode(JSON.parse(%({"message": "pong"}))).should be_nil
  end
end
