require "json"
require "socket"
require "../../spec_helper"
require "../../support/optional_obsctl_rs_compat"
require "../../../src/obsctl/cli/main"
require "../../../src/obsctl/ipc/client_session"
require "../../../src/obsctl/ipc/socket_path"

private GOLDEN_CLI_FIXTURE_ROOT = File.expand_path("../../fixtures/contracts", __DIR__)

private GOLDEN_CLI_SUCCESS_CASES = [
  {name: "status", args: ["status"], json: "cli/json/status_success.json", human: "cli/human/status_success.txt", command_name: "status", target: nil, percent: nil},
  {name: "server-status", args: ["server-status"], json: "cli/json/server_status_success.json", human: "cli/human/server_status_success.txt", command_name: "get_server_status", target: nil, percent: nil},
  {name: "obs-status", args: ["obs-status"], json: "cli/json/obs_status_success.json", human: "cli/human/obs_status_success.txt", command_name: "get_obs_status", target: nil, percent: nil},
  {name: "scene", args: ["scene", "main"], json: "cli/json/scene_success.json", human: "cli/human/scene_success.txt", command_name: "set_scene", target: "main", percent: nil},
  {name: "mute", args: ["mute", "mic"], json: "cli/json/mute_success.json", human: "cli/human/mute_success.txt", command_name: "mute", target: "mic", percent: nil},
  {name: "unmute", args: ["unmute", "mic"], json: "cli/json/unmute_success.json", human: "cli/human/unmute_success.txt", command_name: "unmute", target: "mic", percent: nil},
  {name: "toggle-mute", args: ["toggle-mute", "mic"], json: "cli/json/toggle_mute_success.json", human: "cli/human/toggle_mute_success.txt", command_name: "toggle_mute", target: "mic", percent: nil},
  {name: "vol", args: ["vol", "mic", "70"], json: "cli/json/vol_success.json", human: "cli/human/vol_success.txt", command_name: "set_volume", target: "mic", percent: 70},
  {name: "dump-config", args: ["dump-config"], json: "cli/json/dump_config_success.json", human: "cli/human/dump_config_success.txt", command_name: "dump_config", target: nil, percent: nil},
  {name: "reload-config", args: ["reload-config"], json: "cli/json/reload_config_success.json", human: "cli/human/reload_config_success.txt", command_name: "reload_config", target: nil, percent: nil},
  {name: "reconnect", args: ["reconnect"], json: "cli/json/reconnect_success.json", human: "cli/human/reconnect_success.txt", command_name: "reconnect_obs", target: nil, percent: nil},
  {name: "shutdown-server", args: ["shutdown-server"], json: "cli/json/shutdown_server_success.json", human: "cli/human/shutdown_server_success.txt", command_name: "shutdown_server", target: nil, percent: nil},
]

private GOLDEN_CLI_ERROR_CASES = [
  {name: "obs-unavailable", args: ["scene", "main"], fixture: "cli/json/obs_unavailable_error.json", command_name: "set_scene", target: "main", percent: nil, exit_code: 3},
  {name: "config-invalid", args: ["reload-config"], fixture: "cli/json/config_invalid_error.json", command_name: "reload_config", target: nil, percent: nil, exit_code: 2},
  {name: "timeout", args: ["scene", "main"], fixture: "cli/json/timeout_error.json", command_name: "set_scene", target: "main", percent: nil, exit_code: 3},
  {name: "protocol-error", args: ["status"], fixture: "cli/json/protocol_error.json", command_name: "status", target: nil, percent: nil, exit_code: 6},
]

private def golden_cli_fixture(path : String) : String
  File.read(File.join(GOLDEN_CLI_FIXTURE_ROOT, path))
end

private def golden_cli_json(path : String) : String
  golden_cli_fixture(path).strip
end

private def golden_cli_response_from_envelope(envelope_json : String) : Obsctl::IPC::Response
  envelope = JSON.parse(envelope_json)
  error = envelope["error"].raw.nil? ? nil : Obsctl::IPC::ErrorPayload.new(
    envelope["error"]["code"].as_s,
    envelope["error"]["message"].as_s
  )

  Obsctl::IPC::Response.new(
    "req-000001",
    envelope["ok"].as_bool,
    envelope["result"].raw.nil? ? nil : envelope["result"],
    error
  )
end

private def with_golden_cli_runtime(&)
  runtime_dir = File.join(Dir.tempdir, "obsctl-golden-cli-#{Random.rand(1_000_000)}")
  previous_runtime_dir = ENV["XDG_RUNTIME_DIR"]?
  ENV["XDG_RUNTIME_DIR"] = runtime_dir
  yield runtime_dir
ensure
  if previous_runtime_dir
    ENV["XDG_RUNTIME_DIR"] = previous_runtime_dir
  else
    ENV.delete("XDG_RUNTIME_DIR")
  end
  FileUtils.rm_rf(runtime_dir) if runtime_dir
end

private def with_golden_cli_daemon_response(response : Obsctl::IPC::Response, &)
  socket_path = Obsctl::IPC::SocketPath.resolve
  Obsctl::IPC::SocketPath.ensure_parent(socket_path)
  server = UNIXServer.new(socket_path)
  File.chmod(socket_path, 0o600)
  received = Channel(Obsctl::IPC::Request).new(1)

  spawn do
    socket = server.accept
    session = Obsctl::IPC::ClientSession.new(socket)
    request = session.read_message.as(Obsctl::IPC::Request)
    received.send(request)
    session.write_message(response)
    session.close
  end

  yield received
ensure
  server.try(&.close)
  File.delete(socket_path) if socket_path && File.exists?(socket_path)
end

private def run_golden_cli(args : Array(String), runtime_dir : String) : Tuple(Int32, String, String)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  config_path = File.join(runtime_dir, "missing-config.yml")
  exit_code = Obsctl::CLI::Main.run(["--config", config_path] + args, nil, stdout, stderr)
  {exit_code, stdout.to_s, stderr.to_s}
end

private def assert_golden_cli_request(
  request : Obsctl::IPC::Request,
  command_name : String,
  target : String?,
  percent : Int32?,
) : Nil
  command = request.command.not_nil!
  command.name.should eq(command_name)
  command.target.should eq(target)
  command.percent.should eq(percent)
end

describe "golden CLI proxy contracts" do
  GOLDEN_CLI_SUCCESS_CASES.each do |contract_case|
    it "freezes human output for #{contract_case[:name]}" do
      response = golden_cli_response_from_envelope(golden_cli_json(contract_case[:json]))

      with_golden_cli_runtime do |runtime_dir|
        with_golden_cli_daemon_response(response) do |received|
          exit_code, stdout, stderr = run_golden_cli(contract_case[:args], runtime_dir)

          assert_golden_cli_request(
            received.receive,
            contract_case[:command_name],
            contract_case[:target],
            contract_case[:percent]
          )
          exit_code.should eq(0)
          stdout.should eq(golden_cli_fixture(contract_case[:human]))
          stderr.should eq("")
        end
      end
    end

    it "freezes JSON success envelope for #{contract_case[:name]}" do
      response = golden_cli_response_from_envelope(golden_cli_json(contract_case[:json]))

      with_golden_cli_runtime do |runtime_dir|
        with_golden_cli_daemon_response(response) do |received|
          exit_code, stdout, stderr = run_golden_cli(["--json"] + contract_case[:args], runtime_dir)

          assert_golden_cli_request(
            received.receive,
            contract_case[:command_name],
            contract_case[:target],
            contract_case[:percent]
          )
          exit_code.should eq(0)
          stdout.should eq("#{golden_cli_json(contract_case[:json])}\n")
          stderr.should eq("")
        end
      end
    end
  end

  GOLDEN_CLI_ERROR_CASES.each do |contract_case|
    it "freezes JSON #{contract_case[:name]} envelope" do
      response = golden_cli_response_from_envelope(golden_cli_json(contract_case[:fixture]))

      with_golden_cli_runtime do |runtime_dir|
        with_golden_cli_daemon_response(response) do |received|
          exit_code, stdout, stderr = run_golden_cli(["--json"] + contract_case[:args], runtime_dir)

          assert_golden_cli_request(
            received.receive,
            contract_case[:command_name],
            contract_case[:target],
            contract_case[:percent]
          )
          exit_code.should eq(contract_case[:exit_code])
          stdout.should eq("#{golden_cli_json(contract_case[:fixture])}\n")
          stderr.should eq("")
        end
      end
    end
  end

  it "freezes JSON parse-error envelope before sending IPC" do
    with_golden_cli_runtime do |runtime_dir|
      exit_code, stdout, stderr = run_golden_cli(["--json", "vol", "mic", "101"], runtime_dir)

      exit_code.should eq(5)
      stdout.should eq("#{golden_cli_json("cli/json/parse_error.json")}\n")
      stderr.should eq("")
    end
  end

  it "freezes JSON server-unavailable envelope when the daemon socket is absent" do
    with_golden_cli_runtime do |runtime_dir|
      exit_code, stdout, stderr = run_golden_cli(["--json", "status"], runtime_dir)

      exit_code.should eq(3)
      stdout.should eq("#{golden_cli_json("cli/json/server_unavailable_error.json")}\n")
      stderr.should eq("")
    end
  end

  it "optionally matches obsctl-rs CLI golden fixtures in strict compatibility mode" do
    Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(GOLDEN_CLI_FIXTURE_ROOT, "cli/")
  end
end
