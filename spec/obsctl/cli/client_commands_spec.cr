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
