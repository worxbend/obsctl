require "json"
require "../../spec_helper"
require "../../../src/obsctl/cli/client_commands"
require "../../../src/obsctl/domain/command_parser"
require "../../../src/obsctl/ipc/protocol"

private CONTRACT_FIXTURE_DIR = File.expand_path("../../fixtures/contracts", __DIR__)

private class ContractCaptureUnixClient < Obsctl::IPC::UnixClient
  getter request_payload : Obsctl::IPC::Request?

  def initialize
    super("/tmp/obsctl-contract-unused.sock")
  end

  def request(request : Obsctl::IPC::Request) : Obsctl::IPC::Response
    @request_payload = request
    Obsctl::IPC::Response.new(request.id, true, JSON.parse(%({"message":"accepted"})))
  end
end

private def contract_fixture_json(name : String) : String
  File.read(File.join(CONTRACT_FIXTURE_DIR, name)).strip
end

private def normalized_json(json : String) : JSON::Any
  JSON.parse(json)
end

describe "IPC public contract" do
  it "encodes the scene command input as the frozen typed IPC payload" do
    command = Obsctl::Domain::CommandParser.new.parse("/scene main")
    unix_client = ContractCaptureUnixClient.new

    Obsctl::CLI::ClientCommands.new(unix_client).request(command)

    request = unix_client.request_payload.not_nil!
    encoded = Obsctl::IPC::Codec.new.encode(request).strip

    normalized_json(encoded).should eq(normalized_json(contract_fixture_json("ipc_set_scene_request.json")))
    request.command?.should be_true
    request.command.not_nil!.name.should eq("set_scene")
    request.command.not_nil!.target.should eq("main")
  end

  it "decodes the frozen set-scene fixture into the typed request model" do
    decoded = Obsctl::IPC::Codec.new.decode(contract_fixture_json("ipc_set_scene_request.json"))
      .as(Obsctl::IPC::Request)

    decoded.id.should eq("req-000001")
    decoded.type.should eq(Obsctl::IPC::Request::TYPE_COMMAND)
    decoded.command.not_nil!.name.should eq("set_scene")
    decoded.command.not_nil!.target.should eq("main")
  end
end
