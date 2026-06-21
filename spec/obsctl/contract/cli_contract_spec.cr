require "json"
require "socket"
require "../../spec_helper"
require "../../../src/obsctl/cli/main"
require "../../../src/obsctl/ipc/client_session"
require "../../../src/obsctl/ipc/socket_path"

private CLI_CONTRACT_FIXTURE_DIR = File.expand_path("../../fixtures/contracts", __DIR__)

private def cli_contract_fixture_json(name : String) : String
  File.read(File.join(CLI_CONTRACT_FIXTURE_DIR, name)).strip
end

private def cli_contract_fixture(name : String) : JSON::Any
  JSON.parse(cli_contract_fixture_json(name))
end

private def cli_contract_response_from_envelope(envelope : JSON::Any) : Obsctl::IPC::Response
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

private def with_cli_contract_runtime(&)
  runtime_dir = File.join(Dir.tempdir, "obsctl-cli-contract-#{Random.rand(1_000_000)}")
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

private def with_cli_contract_daemon_response(response : Obsctl::IPC::Response, &)
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

private def run_cli_contract(args : Array(String)) : Tuple(Int32, String, String)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  exit_code = Obsctl::CLI::Main.run(args, nil, stdout, stderr)
  {exit_code, stdout.to_s, stderr.to_s}
end

describe "CLI public contract" do
  it "prints the frozen human status output and keeps stderr empty on success" do
    envelope = cli_contract_fixture("cli_status_success.json")
    response = cli_contract_response_from_envelope(envelope)

    with_cli_contract_runtime do
      with_cli_contract_daemon_response(response) do |received|
        exit_code, stdout, stderr = run_cli_contract(["status"])

        received.receive.command.not_nil!.name.should eq("status")
        exit_code.should eq(0)
        stdout.should eq("server:\n  pid: 4242\n  uptime_seconds: 37\n  socket_path: /tmp/obsctl-contract/obsctl.sock\n  client_count: 2\n  dropped_reconnect_diagnostic_logs: 4\n  obs_connected: true\n  reconnecting: false\n  last_connected_at: 2026-06-20T12:00:00Z\n  last_disconnected_at: -\n  last_reconnect_attempt_at: 2026-06-20T11:59:59Z\n  last_connection_failed_at: -\n  last_error: -\nobs:\n  connected: true\n  current_scene: Main Camera\n  scenes:\n    * Main Camera\n    - Break\n  audio:\n    - Mic/Aux live volume=72%\n")
        stderr.should eq("")
      end
    end
  end

  it "prints daemon command failures to stderr only in human mode" do
    envelope = cli_contract_fixture("cli_scene_error.json")
    response = cli_contract_response_from_envelope(envelope)

    with_cli_contract_runtime do
      with_cli_contract_daemon_response(response) do |received|
        exit_code, stdout, stderr = run_cli_contract(["scene", "missing"])

        request = received.receive
        request.command.not_nil!.name.should eq("set_scene")
        request.command.not_nil!.target.should eq("missing")
        exit_code.should eq(4)
        stdout.should eq("")
        stderr.should eq("scene not found: missing\n")
      end
    end
  end

  it "emits the exact frozen JSON status envelope on stdout only" do
    envelope = cli_contract_fixture("cli_status_success.json")
    response = cli_contract_response_from_envelope(envelope)

    with_cli_contract_runtime do
      with_cli_contract_daemon_response(response) do |received|
        exit_code, stdout, stderr = run_cli_contract(["--json", "status"])

        received.receive.command.not_nil!.name.should eq("status")
        exit_code.should eq(0)
        stdout.should eq("#{cli_contract_fixture_json("cli_status_success.json")}\n")
        stderr.should eq("")
      end
    end
  end

  it "emits the exact frozen JSON error envelope on stdout only" do
    envelope = cli_contract_fixture("cli_scene_error.json")
    response = cli_contract_response_from_envelope(envelope)

    with_cli_contract_runtime do
      with_cli_contract_daemon_response(response) do |received|
        exit_code, stdout, stderr = run_cli_contract(["scene", "missing", "--json"])

        request = received.receive
        request.command.not_nil!.name.should eq("set_scene")
        request.command.not_nil!.target.should eq("missing")
        exit_code.should eq(4)
        stdout.should eq("#{cli_contract_fixture_json("cli_scene_error.json")}\n")
        stderr.should eq("")
      end
    end
  end
end
