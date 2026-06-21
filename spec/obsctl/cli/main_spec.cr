require "json"
require "socket"
require "../../spec_helper"
require "../../../src/obsctl/cli/main"
require "../../../src/obsctl/ipc/client_session"
require "../../../src/obsctl/ipc/socket_path"

private class FakeCliSystemCommandRunner < Obsctl::Service::SystemCommandRunner
  getter calls = [] of Tuple(String, Array(String))

  def run(command : String, args : Array(String)) : Process::Status
    @calls << {command, args}
    Process::Status.new(0)
  end
end

private def with_cli_json_runtime(&)
  runtime_dir = File.join(Dir.tempdir, "obsctl-cli-json-#{Random.rand(1_000_000)}")
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

private def with_fake_ipc_response(response : Obsctl::IPC::Response, &)
  socket_path = Obsctl::IPC::SocketPath.resolve
  Obsctl::IPC::SocketPath.ensure_parent(socket_path)
  server = UNIXServer.new(socket_path)
  File.chmod(socket_path, 0o600)
  received = Channel(Obsctl::IPC::Request).new(1)

  spawn do
    socket = server.accept
    session = Obsctl::IPC::ClientSession.new(socket)
    message = session.read_message
    received.send(message.as(Obsctl::IPC::Request))
    session.write_message(response)
    session.close
  end

  yield received
ensure
  server.try(&.close)
  File.delete(socket_path) if socket_path && File.exists?(socket_path)
end

private def run_cli_json(args : Array(String)) : Tuple(Int32, String, String)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  exit_code = Obsctl::CLI::Main.run(args, nil, stdout, stderr)
  {exit_code, stdout.to_s, stderr.to_s}
end

private def parse_single_json(stdout : String) : JSON::Any
  lines = stdout.lines
  lines.size.should eq(1)
  JSON.parse(lines[0])
end

describe Obsctl::CLI::Main do
  it "returns config error for missing config when command requires config" do
    path = "/tmp/obsctl-missing-#{Random.rand(1_000_000)}.yml"
    Obsctl::CLI::Main.run(["--config", path, "validate-config"]).should eq(2)
  end

  it "returns server unavailable for thin client commands when IPC is missing" do
    runtime_dir = File.join(Dir.tempdir, "obsctl-cli-main-#{Random.rand(1_000_000)}")
    previous_runtime_dir = ENV["XDG_RUNTIME_DIR"]?
    ENV["XDG_RUNTIME_DIR"] = runtime_dir

    Obsctl::CLI::Main.run(["status"]).should eq(3)
  ensure
    if previous_runtime_dir
      ENV["XDG_RUNTIME_DIR"] = previous_runtime_dir
    else
      ENV.delete("XDG_RUNTIME_DIR")
    end
    FileUtils.rm_rf(runtime_dir) if runtime_dir
  end

  it "prints combined human status through the IPC client path" do
    with_cli_json_runtime do
      result = JSON.parse(<<-JSON)
      {
        "server": {
          "pid": 123,
          "uptime_seconds": 5,
          "socket_path": "/tmp/obsctl.sock",
          "client_count": 1,
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

      with_fake_ipc_response(response) do |received|
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        exit_code = Obsctl::CLI::Main.run(["status"], nil, stdout, stderr)
        request = received.receive

        request.command.try(&.name).should eq("status")
        exit_code.should eq(0)
        stderr.to_s.should eq("")
        stdout.to_s.should contain("server:\n  pid: 123")
        stdout.to_s.should contain("  dropped_reconnect_diagnostic_logs: 3")
        stdout.to_s.should contain("  last_connected_at: 2026-06-20T12:00:00Z")
        stdout.to_s.should contain("  last_disconnected_at: 2026-06-20T11:55:00Z")
        stdout.to_s.should contain("  last_reconnect_attempt_at: 2026-06-20T11:59:59Z")
        stdout.to_s.should contain("  last_connection_failed_at: 2026-06-20T11:58:00Z")
        stdout.to_s.should contain("obs:\n  connected: true")
        stdout.to_s.should contain("  current_scene: Main Camera")
      end
    end
  end

  it "prints daemon human status with every reconnect timestamp field through the IPC client path" do
    with_cli_json_runtime do
      result = JSON.parse(<<-JSON)
      {
        "pid": 123,
        "uptime_seconds": 5,
        "socket_path": "/tmp/obsctl.sock",
        "client_count": 1,
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

      with_fake_ipc_response(response) do |received|
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        exit_code = Obsctl::CLI::Main.run(["server-status"], nil, stdout, stderr)
        request = received.receive

        request.command.try(&.name).should eq("get_server_status")
        exit_code.should eq(0)
        stderr.to_s.should eq("")
        stdout.to_s.should contain("last_connected_at: 2026-06-20T12:00:00Z")
        stdout.to_s.should contain("dropped_reconnect_diagnostic_logs: 5")
        stdout.to_s.should contain("last_disconnected_at: 2026-06-20T12:05:00Z")
        stdout.to_s.should contain("last_reconnect_attempt_at: 2026-06-20T12:06:00Z")
        stdout.to_s.should contain("last_connection_failed_at: 2026-06-20T12:07:00Z")
      end
    end
  end

  it "emits a JSON envelope for successful proxy commands" do
    with_cli_json_runtime do
      result = JSON.parse(<<-JSON)
      {
        "server": {
          "pid": 123,
          "uptime_seconds": 5,
          "socket_path": "/tmp/obsctl.sock",
          "client_count": 1,
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
          "scenes": [],
          "audio_inputs": []
        }
      }
      JSON
      response = Obsctl::IPC::Response.new("req-000001", true, result)

      with_fake_ipc_response(response) do |received|
        exit_code, stdout, stderr = run_cli_json(["--json", "status"])
        request = received.receive

        request.command.try(&.name).should eq("status")
        exit_code.should eq(0)
        stderr.should eq("")

        envelope = parse_single_json(stdout)
        envelope["ok"].as_bool.should be_true
        envelope["result"]["server"]["obs_connected"].as_bool.should be_true
        envelope["result"]["server"]["dropped_reconnect_diagnostic_logs"].as_i64.should eq(3)
        envelope["result"]["server"]["last_connected_at"].as_s.should eq("2026-06-20T12:00:00Z")
        envelope["result"]["server"]["last_disconnected_at"].as_s.should eq("2026-06-20T11:55:00Z")
        envelope["result"]["server"]["last_reconnect_attempt_at"].as_s.should eq("2026-06-20T11:59:59Z")
        envelope["result"]["server"]["last_connection_failed_at"].as_s.should eq("2026-06-20T11:58:00Z")
        envelope["result"]["obs"]["connected"].as_bool.should be_true
        envelope["result"]["obs"]["current_scene"].as_s.should eq("Main Camera")
        envelope["error"].raw.should be_nil
        envelope["exit_code"].as_i.should eq(0)
      end
    end
  end

  it "emits a JSON envelope for daemon status with every reconnect timestamp field" do
    with_cli_json_runtime do
      result = JSON.parse(<<-JSON)
      {
        "pid": 123,
        "uptime_seconds": 5,
        "socket_path": "/tmp/obsctl.sock",
        "client_count": 1,
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

      with_fake_ipc_response(response) do |received|
        exit_code, stdout, stderr = run_cli_json(["--json", "server-status"])
        request = received.receive

        request.command.try(&.name).should eq("get_server_status")
        exit_code.should eq(0)
        stderr.should eq("")

        envelope = parse_single_json(stdout)
        envelope["ok"].as_bool.should be_true
        envelope["result"]["dropped_reconnect_diagnostic_logs"].as_i64.should eq(5)
        envelope["result"]["last_connected_at"].as_s.should eq("2026-06-20T12:00:00Z")
        envelope["result"]["last_disconnected_at"].as_s.should eq("2026-06-20T12:05:00Z")
        envelope["result"]["last_reconnect_attempt_at"].as_s.should eq("2026-06-20T12:06:00Z")
        envelope["result"]["last_connection_failed_at"].as_s.should eq("2026-06-20T12:07:00Z")
        envelope["error"].raw.should be_nil
        envelope["exit_code"].as_i.should eq(0)
      end
    end
  end

  it "emits a JSON envelope without startup hints when the server is unavailable" do
    with_cli_json_runtime do
      exit_code, stdout, stderr = run_cli_json(["status", "--json"])

      exit_code.should eq(3)
      stderr.should eq("")

      envelope = parse_single_json(stdout)
      envelope["ok"].as_bool.should be_false
      envelope["result"].raw.should be_nil
      envelope["error"]["code"].as_s.should eq(Obsctl::IPC::ErrorCode::SERVER_UNAVAILABLE)
      envelope["exit_code"].as_i.should eq(exit_code)
    end
  end

  it "emits one JSON envelope for validate-config and keeps warnings on stderr" do
    dir = File.join(Dir.tempdir, "obsctl-cli-validate-json-#{Random.rand(1_000_000)}")
    Dir.mkdir_p(dir)
    path = File.join(dir, "config.yml")
    File.write(path, <<-YAML)
    version: 1
    connection:
      host: 127.0.0.1
      port: 4455
      password_env: ""
      password: "super-secret"
      connect_timeout_ms: 3000
      request_timeout_ms: 2500
    YAML

    exit_code, stdout, stderr = run_cli_json(["--config", path, "validate-config", "--json"])

    exit_code.should eq(0)
    stderr.should contain("warning: plaintext connection.password is configured")
    stderr.should_not contain("super-secret")

    envelope = parse_single_json(stdout)
    envelope["ok"].as_bool.should be_true
    envelope["result"]["message"].as_s.should eq("config valid: #{path}")
    envelope["error"].raw.should be_nil
    envelope["exit_code"].as_i.should eq(exit_code)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "emits a JSON envelope for unsupported commands when JSON is requested" do
    exit_code, stdout, stderr = run_cli_json(["bogus", "--json"])

    exit_code.should eq(5)
    stderr.should eq("")

    envelope = parse_single_json(stdout)
    envelope["ok"].as_bool.should be_false
    envelope["result"].raw.should be_nil
    envelope["error"]["code"].as_s.should eq(Obsctl::IPC::ErrorCode::COMMAND_PARSE_ERROR)
    envelope["error"]["message"].as_s.should eq("JSON output is not supported for command: bogus")
    envelope["exit_code"].as_i.should eq(exit_code)
  end

  it "rejects init in JSON mode before writing config files" do
    dir = File.join(Dir.tempdir, "obsctl-cli-init-json-#{Random.rand(1_000_000)}")
    path = File.join(dir, "config.yml")

    exit_code, stdout, stderr = run_cli_json(["--config", path, "init", "--json"])

    exit_code.should eq(5)
    stderr.should eq("")
    File.exists?(path).should be_false

    envelope = parse_single_json(stdout)
    envelope["ok"].as_bool.should be_false
    envelope["error"]["code"].as_s.should eq(Obsctl::IPC::ErrorCode::COMMAND_PARSE_ERROR)
    envelope["error"]["message"].as_s.should eq("JSON output is not supported for command: init")
    envelope["exit_code"].as_i.should eq(exit_code)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "rejects service commands in JSON mode before invoking systemctl" do
    runner = FakeCliSystemCommandRunner.new
    installer = Obsctl::Service::ServiceInstaller.new(
      service_path: "/tmp/obsctl.service",
      executable_path: "/tmp/obsctl",
      runner: runner
    )
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    exit_code = Obsctl::CLI::Main.run(["service", "status", "--json"], installer, stdout, stderr)

    exit_code.should eq(5)
    stderr.to_s.should eq("")
    runner.calls.should be_empty

    envelope = parse_single_json(stdout.to_s)
    envelope["ok"].as_bool.should be_false
    envelope["error"]["code"].as_s.should eq(Obsctl::IPC::ErrorCode::COMMAND_PARSE_ERROR)
    envelope["error"]["message"].as_s.should eq("JSON output is not supported for command: service")
    envelope["exit_code"].as_i.should eq(exit_code)
  end

  it "emits a JSON envelope for invalid global options when JSON is requested" do
    exit_code, stdout, stderr = run_cli_json(["--json", "--bogus", "status"])

    exit_code.should eq(5)
    stderr.should eq("")

    envelope = parse_single_json(stdout)
    envelope["ok"].as_bool.should be_false
    envelope["result"].raw.should be_nil
    envelope["error"]["code"].as_s.should eq(Obsctl::IPC::ErrorCode::COMMAND_PARSE_ERROR)
    envelope["error"]["message"].as_s.should contain("Invalid option")
    envelope["exit_code"].as_i.should eq(exit_code)
  end

  it "emits a JSON envelope for CLI parse errors before IPC" do
    with_cli_json_runtime do
      exit_code, stdout, stderr = run_cli_json(["scene", "--json"])

      exit_code.should eq(5)
      stderr.should eq("")

      envelope = parse_single_json(stdout)
      envelope["ok"].as_bool.should be_false
      envelope["error"]["code"].as_s.should eq(Obsctl::IPC::ErrorCode::COMMAND_PARSE_ERROR)
      envelope["error"]["message"].as_s.should contain("missing argument")
      envelope["exit_code"].as_i.should eq(exit_code)
    end
  end

  it "emits a JSON envelope for OBS unavailable command failures" do
    with_cli_json_runtime do
      error = Obsctl::IPC::ErrorPayload.new(Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE, "OBS is unavailable")
      response = Obsctl::IPC::Response.new("req-000001", false, nil, error)

      with_fake_ipc_response(response) do
        exit_code, stdout, stderr = run_cli_json(["--json", "mute", "mic"])

        exit_code.should eq(3)
        stderr.should eq("")

        envelope = parse_single_json(stdout)
        envelope["ok"].as_bool.should be_false
        envelope["result"].raw.should be_nil
        envelope["error"]["code"].as_s.should eq(Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE)
        envelope["exit_code"].as_i.should eq(exit_code)
      end
    end
  end

  it "emits a JSON envelope for failed proxy command responses" do
    with_cli_json_runtime do
      error = Obsctl::IPC::ErrorPayload.new(Obsctl::IPC::ErrorCode::SCENE_NOT_FOUND, "scene not found: missing")
      response = Obsctl::IPC::Response.new("req-000001", false, nil, error)

      with_fake_ipc_response(response) do
        exit_code, stdout, stderr = run_cli_json(["--json", "scene", "missing"])

        exit_code.should eq(4)
        stderr.should eq("")

        envelope = parse_single_json(stdout)
        envelope["ok"].as_bool.should be_false
        envelope["result"].raw.should be_nil
        envelope["error"]["code"].as_s.should eq(Obsctl::IPC::ErrorCode::SCENE_NOT_FOUND)
        envelope["error"]["message"].as_s.should eq("scene not found: missing")
        envelope["exit_code"].as_i.should eq(exit_code)
      end
    end
  end

  it "returns command parse error for unsupported log levels" do
    Obsctl::CLI::Main.run(["--log-level", "trace", "status"]).should eq(5)
  end

  it "smoke tests service install through the CLI boundary" do
    dir = File.join(Dir.tempdir, "obsctl-cli-service-#{Random.rand(1_000_000)}")
    service_path = File.join(dir, "obsctl.service")
    runner = FakeCliSystemCommandRunner.new
    installer = Obsctl::Service::ServiceInstaller.new(
      service_path: service_path,
      executable_path: "/tmp/obsctl",
      runner: runner
    )

    Obsctl::CLI::Main.run(["service", "install"], installer).should eq(0)

    File.read(service_path).should contain("ExecStart=/tmp/obsctl server --headless")
    runner.calls.should eq([{"systemctl", ["--user", "daemon-reload"]}])
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "smoke tests service control through the CLI boundary" do
    runner = FakeCliSystemCommandRunner.new
    installer = Obsctl::Service::ServiceInstaller.new(
      service_path: "/tmp/obsctl.service",
      executable_path: "/tmp/obsctl",
      runner: runner
    )

    Obsctl::CLI::Main.run(["service", "start"], installer).should eq(0)

    runner.calls.should eq([{"systemctl", ["--user", "start", "obsctl.service"]}])
  end

  it "writes safe config warnings without exposing plaintext passwords" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        password_env: "",
        password: "super-secret"
      )
    )
    io = IO::Memory.new

    Obsctl::CLI::Main.write_config_warnings(config, io)

    stderr = io.to_s
    stderr.should contain("warning: plaintext connection.password is configured")
    stderr.should_not contain("super-secret")
  end
end
