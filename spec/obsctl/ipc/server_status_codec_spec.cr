require "../../spec_helper"
require "../../../src/obsctl/ipc/server_status_codec"

private alias ServerStatus = Obsctl::IPC::ServerStatus
private alias RecordStatusCodec = Obsctl::IPC::RecordStatusCodec
private alias RecordStatus = Obsctl::OBS::State::RecordStatus

private def full_server_status
  ServerStatus.new(
    pid: 4242_i64,
    uptime_seconds: 37_i64,
    socket_path: "/tmp/obsctl-contract/obsctl.sock",
    client_count: 2,
    dropped_reconnect_diagnostic_logs: 4_i64,
    obs_connected: true,
    reconnecting: false,
    last_connected_at: "2026-06-20T12:00:00Z",
    last_disconnected_at: nil,
    last_reconnect_attempt_at: "2026-06-20T11:59:59Z",
    last_connection_failed_at: nil,
    last_error: nil
  )
end

# The daemon encodes, the CLI decodes, and `docs/commands.md` freezes the shape
# in between. Nothing but agreement between the two halves makes `obsctl
# server-status` print what the daemon actually reported, so the round trip is
# the contract.
describe Obsctl::IPC::ServerStatus do
  it "round trips a fully populated status" do
    original = full_server_status

    ServerStatus.decode(original.encode).should eq(original)
  end

  it "round trips a status whose optional fields are all absent" do
    original = ServerStatus.new

    ServerStatus.decode(original.encode).should eq(original)
  end

  it "writes every key in the frozen order, spelling an absent value null" do
    full_server_status.encode.to_json.should eq(
      %({"pid":4242,"uptime_seconds":37,"socket_path":"/tmp/obsctl-contract/obsctl.sock",) +
      %("client_count":2,"dropped_reconnect_diagnostic_logs":4,"obs_connected":true,) +
      %("reconnecting":false,"last_connected_at":"2026-06-20T12:00:00Z",) +
      %("last_disconnected_at":null,"last_reconnect_attempt_at":"2026-06-20T11:59:59Z",) +
      %("last_connection_failed_at":null,"last_error":null})
    )
  end

  it "reads a payload from a daemon that publishes none of these fields" do
    decoded = ServerStatus.decode(JSON.parse(%({})))

    decoded.pid.should be_nil
    decoded.client_count.should be_nil
    decoded.obs_connected.should be_nil
    decoded.last_error.should be_nil
  end

  it "reads a field of the wrong JSON type as absent rather than raising" do
    decoded = ServerStatus.decode(JSON.parse(%({"pid":"not a number","obs_connected":"yes"})))

    decoded.pid.should be_nil
    decoded.obs_connected.should be_nil
  end
end

describe Obsctl::IPC::RecordStatusCodec do
  it "round trips an active recording" do
    original = RecordStatus.new(
      active: true, paused: false, timecode: "00:00:12.345",
      duration_ms: 12_345_i64, bytes: 987_654_i64)

    RecordStatusCodec.decode(RecordStatusCodec.encode(original)).should eq(original)
  end

  it "round trips a status OBS has said nothing about" do
    original = RecordStatus.new

    RecordStatusCodec.decode(RecordStatusCodec.encode(original)).should eq(original)
  end

  it "leads the payload with the derived one-line message" do
    RecordStatusCodec.encode(RecordStatus.new(active: true, paused: true)).to_json.should eq(
      %({"message":"recording paused","active":true,"paused":true,) +
      %("timecode":null,"duration_ms":null,"bytes":null})
    )
  end

  # The two surfaces word the third state differently, and both wordings are
  # frozen output.
  it "lets the caller name the state OBS has not reported" do
    RecordStatus.new.state("state unknown").should eq("state unknown")
    RecordStatus.new.state("-").should eq("-")
    RecordStatus.new(active: false).state("-").should eq("stopped")
    RecordStatus.new(active: true).state("-").should eq("active")
    RecordStatus.new(active: true, paused: true).state("-").should eq("paused")
  end
end
