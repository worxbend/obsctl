require "json"
require "../../spec_helper"
require "../../../src/obsctl/cli/client_commands"

private class FakeClientCommandsUnixClient < Obsctl::IPC::UnixClient
  getter request_payload : Obsctl::IPC::Request?

  def initialize(@response : Obsctl::IPC::Response)
    super("/tmp/obsctl-unused.sock")
  end

  def request(request : Obsctl::IPC::Request) : Obsctl::IPC::Response
    @request_payload = request
    @response
  end
end

describe Obsctl::CLI::ClientCommands do
  it "sends distinct IPC commands for combined, OBS-only, and daemon-only status" do
    response = Obsctl::IPC::Response.new("req-000001", true, JSON.parse(%({"message":"ok"})))

    status_client = FakeClientCommandsUnixClient.new(response)
    Obsctl::CLI::ClientCommands.new(status_client).request(Obsctl::Domain::StatusCommand.new)
    status_client.request_payload.not_nil!.command.not_nil!.name.should eq("status")

    obs_client = FakeClientCommandsUnixClient.new(response)
    Obsctl::CLI::ClientCommands.new(obs_client).request(Obsctl::Domain::ObsStatusCommand.new)
    obs_client.request_payload.not_nil!.command.not_nil!.name.should eq("get_obs_status")

    server_client = FakeClientCommandsUnixClient.new(response)
    Obsctl::CLI::ClientCommands.new(server_client).request(Obsctl::Domain::ServerStatusCommand.new)
    server_client.request_payload.not_nil!.command.not_nil!.name.should eq("get_server_status")
  end

  it "returns the raw IPC response for JSON envelope callers" do
    result = JSON.parse(%({"message":"muted: Mic/Aux"}))
    response = Obsctl::IPC::Response.new("req-000001", true, result)
    client = FakeClientCommandsUnixClient.new(response)

    raw = Obsctl::CLI::ClientCommands.new(client).request(Obsctl::Domain::MuteCommand.new("mic"))

    raw.should eq(response)
    payload = client.request_payload.not_nil!.command.not_nil!
    payload.name.should eq("mute")
    payload.target.should eq("mic")
  end

  it "formats combined status with separate server and OBS sections" do
    result = JSON.parse(<<-JSON)
    {
      "server": {
        "pid": 123,
        "uptime_seconds": 9,
        "socket_path": "/tmp/obsctl.sock",
        "client_count": 2,
        "dropped_reconnect_diagnostic_logs": 3,
        "obs_connected": true,
        "reconnecting": false,
        "last_connected_at": "2026-06-20T12:00:00Z",
        "last_disconnected_at": "2026-06-20T11:55:00Z",
        "last_reconnect_attempt_at": "2026-06-20T11:59:59Z",
        "last_connection_failed_at": "2026-06-20T11:58:00Z",
        "last_error": null
      },
      "obs": {
        "connected": true,
        "current_scene": "Main Camera",
        "scenes": [{"name":"Main Camera","active":true}],
        "audio_inputs": [{"name":"Mic/Aux","muted":false,"volume_percent":72}]
      }
    }
    JSON
    response = Obsctl::IPC::Response.new("req-000001", true, result)

    output = Obsctl::CLI::ClientCommands.new(FakeClientCommandsUnixClient.new(response))
      .execute(Obsctl::Domain::StatusCommand.new)
      .message

    output.should contain("server:\n  pid: 123")
    output.should contain("  socket_path: /tmp/obsctl.sock")
    output.should contain("  dropped_reconnect_diagnostic_logs: 3")
    output.should contain("  last_connected_at: 2026-06-20T12:00:00Z")
    output.should contain("  last_disconnected_at: 2026-06-20T11:55:00Z")
    output.should contain("  last_reconnect_attempt_at: 2026-06-20T11:59:59Z")
    output.should contain("  last_connection_failed_at: 2026-06-20T11:58:00Z")
    output.should contain("obs:\n  connected: true")
    output.should contain("  current_scene: Main Camera")
  end

  it "formats daemon status with every reconnect timestamp field" do
    result = JSON.parse(<<-JSON)
    {
      "pid": 123,
      "uptime_seconds": 9,
      "socket_path": "/tmp/obsctl.sock",
      "client_count": 2,
      "dropped_reconnect_diagnostic_logs": 5,
      "obs_connected": false,
      "reconnecting": true,
      "last_connected_at": "2026-06-20T12:00:00Z",
      "last_disconnected_at": "2026-06-20T12:05:00Z",
      "last_reconnect_attempt_at": "2026-06-20T12:06:00Z",
      "last_connection_failed_at": "2026-06-20T12:07:00Z",
      "last_error": "connection failed"
    }
    JSON
    response = Obsctl::IPC::Response.new("req-000001", true, result)

    output = Obsctl::CLI::ClientCommands.new(FakeClientCommandsUnixClient.new(response))
      .execute(Obsctl::Domain::ServerStatusCommand.new)
      .message

    output.should contain("last_connected_at: 2026-06-20T12:00:00Z")
    output.should contain("dropped_reconnect_diagnostic_logs: 5")
    output.should contain("last_disconnected_at: 2026-06-20T12:05:00Z")
    output.should contain("last_reconnect_attempt_at: 2026-06-20T12:06:00Z")
    output.should contain("last_connection_failed_at: 2026-06-20T12:07:00Z")
  end

  it "keeps formatting older daemon status payloads without last connection failure time" do
    result = JSON.parse(<<-JSON)
    {
      "pid": 123,
      "uptime_seconds": 9,
      "socket_path": "/tmp/obsctl.sock",
      "client_count": 2,
      "obs_connected": true,
      "reconnecting": false,
      "last_connected_at": "2026-06-20T12:00:00Z",
      "last_disconnected_at": null,
      "last_reconnect_attempt_at": "2026-06-20T11:59:59Z",
      "last_error": null
    }
    JSON
    response = Obsctl::IPC::Response.new("req-000001", true, result)

    output = Obsctl::CLI::ClientCommands.new(FakeClientCommandsUnixClient.new(response))
      .execute(Obsctl::Domain::ServerStatusCommand.new)
      .message

    output.should contain("dropped_reconnect_diagnostic_logs: 0")
    output.should contain("last_connection_failed_at: -")
  end

  it "maps every canonical IPC error to an audited process exit code" do
    expected = {
      Obsctl::IPC::ErrorCode::CONFIG_INVALID        => Obsctl::Domain::ExitCode::Config,
      Obsctl::IPC::ErrorCode::SERVER_UNAVAILABLE    => Obsctl::Domain::ExitCode::Connection,
      Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE       => Obsctl::Domain::ExitCode::Connection,
      Obsctl::IPC::ErrorCode::REQUEST_TIMEOUT       => Obsctl::Domain::ExitCode::Connection,
      Obsctl::IPC::ErrorCode::OBS_REQUEST_FAILED    => Obsctl::Domain::ExitCode::ObsRequest,
      Obsctl::IPC::ErrorCode::SCENE_NOT_FOUND       => Obsctl::Domain::ExitCode::ObsRequest,
      Obsctl::IPC::ErrorCode::AUDIO_INPUT_NOT_FOUND => Obsctl::Domain::ExitCode::ObsRequest,
      Obsctl::IPC::ErrorCode::ALIAS_AMBIGUOUS       => Obsctl::Domain::ExitCode::CommandParse,
      Obsctl::IPC::ErrorCode::COMMAND_PARSE_ERROR   => Obsctl::Domain::ExitCode::CommandParse,
      Obsctl::IPC::ErrorCode::IPC_PROTOCOL_ERROR    => Obsctl::Domain::ExitCode::Ipc,
      Obsctl::IPC::ErrorCode::SHUTDOWN_DISABLED     => Obsctl::Domain::ExitCode::CommandParse,
      Obsctl::IPC::ErrorCode::SERVER_ERROR          => Obsctl::Domain::ExitCode::Failure,
    }

    expected.keys.sort.should eq(Obsctl::IPC::ErrorCode::CODES.sort)
    expected[Obsctl::IPC::ErrorCode::ALIAS_AMBIGUOUS].value.should eq(5)

    expected.each do |code, exit_code|
      Obsctl::CLI::ClientCommands.exit_code_for(
        Obsctl::IPC::ErrorPayload.new(code, "safe message")
      ).should eq(exit_code)
    end
  end

  it "maps public domain errors to canonical IPC errors and audited CLI exit codes" do
    cases = [
      {Obsctl::Domain::ConfigInvalid.new("bad config").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::CONFIG_INVALID, Obsctl::Domain::ExitCode::Config},
      {Obsctl::Domain::ConfigNotFound.new("/tmp/missing.yml").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::CONFIG_INVALID, Obsctl::Domain::ExitCode::Config},
      {Obsctl::Domain::ServerUnavailable.new.as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::SERVER_UNAVAILABLE, Obsctl::Domain::ExitCode::Connection},
      {Obsctl::Domain::IpcConnectionFailed.new("socket missing").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::SERVER_UNAVAILABLE, Obsctl::Domain::ExitCode::Connection},
      {Obsctl::Domain::ObsUnavailable.new.as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE, Obsctl::Domain::ExitCode::Connection},
      {Obsctl::Domain::ConnectionFailed.new("connect failed").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE, Obsctl::Domain::ExitCode::Connection},
      {Obsctl::Domain::AuthenticationFailed.new.as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE, Obsctl::Domain::ExitCode::Connection},
      {Obsctl::Domain::RequestTimeout.new("GetVersion").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::REQUEST_TIMEOUT, Obsctl::Domain::ExitCode::Connection},
      {Obsctl::Domain::ObsRequestFailed.new("SetCurrentProgramScene", "failed").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::OBS_REQUEST_FAILED, Obsctl::Domain::ExitCode::ObsRequest},
      {Obsctl::Domain::SceneNotFound.new("missing").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::SCENE_NOT_FOUND, Obsctl::Domain::ExitCode::ObsRequest},
      {Obsctl::Domain::AudioInputNotFound.new("missing").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::AUDIO_INPUT_NOT_FOUND, Obsctl::Domain::ExitCode::ObsRequest},
      {Obsctl::Domain::AliasAmbiguous.new("scene", "cam").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::ALIAS_AMBIGUOUS, Obsctl::Domain::ExitCode::CommandParse},
      {Obsctl::Domain::CommandParseError.new("bad command").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::COMMAND_PARSE_ERROR, Obsctl::Domain::ExitCode::CommandParse},
      {Obsctl::Domain::CommandParseError.new("remote shutdown is disabled").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::SHUTDOWN_DISABLED, Obsctl::Domain::ExitCode::CommandParse},
      {Obsctl::Domain::IpcProtocolError.new("bad frame").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::IPC_PROTOCOL_ERROR, Obsctl::Domain::ExitCode::Ipc},
      {Obsctl::Domain::ServiceInstallFailed.new("systemctl failed").as(Obsctl::Domain::ObsctlError), Obsctl::IPC::ErrorCode::SERVER_ERROR, Obsctl::Domain::ExitCode::Failure},
    ]

    cases.each do |error, code, exit_code|
      payload = Obsctl::IPC::ErrorPayload.from_exception(error)

      payload.code.should eq(code)
      Obsctl::CLI::ClientCommands.exit_code_for(payload).should eq(exit_code)
    end
  end
end
