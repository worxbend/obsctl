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

  it "maps canonical IPC errors to process exit codes" do
    Obsctl::CLI::ClientCommands.exit_code_for(
      Obsctl::IPC::ErrorPayload.new(Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE, "OBS is unavailable")
    ).should eq(Obsctl::Domain::ExitCode::Connection)

    Obsctl::CLI::ClientCommands.exit_code_for(
      Obsctl::IPC::ErrorPayload.new(Obsctl::IPC::ErrorCode::SCENE_NOT_FOUND, "scene not found")
    ).should eq(Obsctl::Domain::ExitCode::ObsRequest)
  end
end
