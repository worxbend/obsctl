require "json"
require "../../spec_helper"
require "../../support/optional_obsctl_rs_compat"
require "../../../src/obsctl/cli/client_commands"
require "../../../src/obsctl/domain/command_parser"
require "../../../src/obsctl/ipc/protocol"

private GOLDEN_IPC_FIXTURE_ROOT = File.expand_path("../../fixtures/contracts", __DIR__)

private GOLDEN_IPC_CASES = [
  {name: "status", line: "/status", fixture: "ipc/status_request.json", command_name: "status", target: nil, percent: nil},
  {name: "server-status", line: "/server-status", fixture: "ipc/server_status_request.json", command_name: "get_server_status", target: nil, percent: nil},
  {name: "obs-status", line: "/obs-status", fixture: "ipc/obs_status_request.json", command_name: "get_obs_status", target: nil, percent: nil},
  {name: "scene", line: "/scene main", fixture: "ipc/scene_request.json", command_name: "set_scene", target: "main", percent: nil},
  {name: "mute", line: "/mute mic", fixture: "ipc/mute_request.json", command_name: "mute", target: "mic", percent: nil},
  {name: "unmute", line: "/unmute mic", fixture: "ipc/unmute_request.json", command_name: "unmute", target: "mic", percent: nil},
  {name: "toggle-mute", line: "/toggle-mute mic", fixture: "ipc/toggle_mute_request.json", command_name: "toggle_mute", target: "mic", percent: nil},
  {name: "vol", line: "/vol mic 70", fixture: "ipc/vol_request.json", command_name: "set_volume", target: "mic", percent: 70},
  {name: "dump-config", line: "/dump-config", fixture: "ipc/dump_config_request.json", command_name: "dump_config", target: nil, percent: nil},
  {name: "reload-config", line: "/reload-config", fixture: "ipc/reload_config_request.json", command_name: "reload_config", target: nil, percent: nil},
  {name: "reconnect", line: "/reconnect", fixture: "ipc/reconnect_request.json", command_name: "reconnect_obs", target: nil, percent: nil},
  {name: "shutdown-server", line: "/shutdown-server", fixture: "ipc/shutdown_server_request.json", command_name: "shutdown_server", target: nil, percent: nil},
]

private class GoldenIpcCaptureUnixClient < Obsctl::IPC::UnixClient
  getter request_payload : Obsctl::IPC::Request?

  def initialize
    super("/tmp/obsctl-golden-ipc-unused.sock")
  end

  def request(request : Obsctl::IPC::Request) : Obsctl::IPC::Response
    @request_payload = request
    Obsctl::IPC::Response.new(request.id, true, JSON.parse(%({"message":"accepted"})))
  end
end

private def golden_ipc_fixture(path : String) : String
  File.read(File.join(GOLDEN_IPC_FIXTURE_ROOT, path)).strip
end

private def assert_golden_ipc_request(
  request : Obsctl::IPC::Request,
  command_name : String,
  target : String?,
  percent : Int32?,
) : Nil
  request.id.should eq("req-000001")
  request.type.should eq(Obsctl::IPC::Request::TYPE_COMMAND)
  command = request.command.not_nil!
  command.name.should eq(command_name)
  command.target.should eq(target)
  command.percent.should eq(percent)
end

describe "golden IPC proxy contracts" do
  GOLDEN_IPC_CASES.each do |contract_case|
    it "encodes #{contract_case[:name]} as the frozen typed IPC payload" do
      command = Obsctl::Domain::CommandParser.new.parse(contract_case[:line])
      unix_client = GoldenIpcCaptureUnixClient.new

      Obsctl::CLI::ClientCommands.new(unix_client).request(command)

      request = unix_client.request_payload.not_nil!
      encoded = Obsctl::IPC::Codec.new.encode(request).strip

      encoded.should eq(golden_ipc_fixture(contract_case[:fixture]))
      assert_golden_ipc_request(
        request,
        contract_case[:command_name],
        contract_case[:target],
        contract_case[:percent]
      )
    end

    it "decodes the frozen #{contract_case[:name]} fixture into the typed request model" do
      decoded = Obsctl::IPC::Codec.new.decode(golden_ipc_fixture(contract_case[:fixture]))
        .as(Obsctl::IPC::Request)

      assert_golden_ipc_request(
        decoded,
        contract_case[:command_name],
        contract_case[:target],
        contract_case[:percent]
      )
    end
  end

  it "matches obsctl-rs IPC golden fixtures when the sibling repository is present" do
    Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(GOLDEN_IPC_FIXTURE_ROOT, "ipc/")
  end
end
