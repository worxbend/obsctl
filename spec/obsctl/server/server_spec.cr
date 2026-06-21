require "../../spec_helper"
require "../../../src/obsctl/server/server"
require "../../../src/obsctl/ipc/protocol"
require "../../../src/obsctl/obs/protocol/event_subscription"
require "../../../src/obsctl/runtime/logger"
require "../../support/fake_obs_server"
require "../../support/tcp_gate"

private def temp_socket_path : String
  File.join(Dir.tempdir, "obsctl-server-spec-#{Random.rand(1_000_000)}.sock")
end

private def next_server_spec_websocket_connection_id(
  obs : Obsctl::SpecSupport::FakeObsServer,
  timeout : Time::Span = 2.seconds,
) : Int64
  obs.next_accepted_websocket_connection_id(timeout) || raise "fake OBS did not accept WebSocket connection"
end

describe Obsctl::Server::Server do
  it "starts IPC and reports OBS unavailable while keeping the server alive" do
    path = temp_socket_path
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: 1,
        password_env: "",
        request_timeout_ms: 100,
        reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
      )
    )
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    until File.exists?(path)
      Fiber.yield
    end

    client = Obsctl::IPC::UnixClient.new(path)
    response = client.request(
      Obsctl::IPC::Request.new(
        "req-status",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("get_obs_status")
      )
    )

    response.ok.should be_true
    response.result.not_nil!["connected"].as_bool.should be_false

    status = wait_for_server_status(client) { |data| !data["last_connection_failed_at"].raw.nil? }
    status["obs_connected"].as_bool.should be_false
    status["last_connected_at"].raw.should be_nil
    status["last_disconnected_at"].raw.should be_nil
    parse_rfc3339(status["last_reconnect_attempt_at"])
    parse_rfc3339(status["last_connection_failed_at"])
    status["last_error"].as_s.should_not be_empty
  ensure
    server.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "rejects explicit reconnect when reconnect is disabled and the startup supervisor exited" do
    obs = nil.as(Obsctl::SpecSupport::FakeObsServer?)
    gate = nil.as(Obsctl::SpecSupport::TcpGate?)
    path = temp_socket_path
    gate = Obsctl::SpecSupport::TcpGate.new
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: gate.port,
        password_env: "",
        connect_timeout_ms: 100,
        request_timeout_ms: 100
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
    )
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    wait_for_socket(path)

    client = Obsctl::IPC::UnixClient.new(path)
    failed_status = wait_for_server_status(client) do |data|
      !data["last_connection_failed_at"].raw.nil? && !data["reconnecting"].as_bool
    end
    failed_status["obs_connected"].as_bool.should be_false
    failed_status["last_error"].as_s.should_not contain("OBS reconnect requested")

    obs = gate.open_fake_obs

    reconnect = client.request(
      Obsctl::IPC::Request.new(
        "req-reconnect-after-supervisor-exit",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("reconnect_obs")
      )
    )

    reconnect.ok.should be_false
    reconnect.error.not_nil!.code.should eq(Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE)
    reconnect.error.not_nil!.message.should eq("OBS supervisor is not running; restart the server or enable reconnect.")
    obs.next_identify(250.milliseconds).should be_nil

    status = client.request(
      Obsctl::IPC::Request.new(
        "req-status-after-failed-reconnect",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("status")
      )
    )
    status.ok.should be_true
    status.result.not_nil!["server"]["obs_connected"].as_bool.should be_false
    status.result.not_nil!["server"]["last_error"].as_s.should_not contain("OBS reconnect requested")
    status.result.not_nil!["obs"]["connected"].as_bool.should be_false
    status.result.not_nil!["obs"]["last_error"].as_s.should_not contain("OBS reconnect requested")
  ensure
    obs.try(&.stop)
    gate.try(&.release)
    server.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "wakes retry backoff when explicit reconnect is requested over IPC" do
    obs = nil.as(Obsctl::SpecSupport::FakeObsServer?)
    gate = nil.as(Obsctl::SpecSupport::TcpGate?)
    path = temp_socket_path
    gate = Obsctl::SpecSupport::TcpGate.new
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: gate.port,
        password_env: "",
        connect_timeout_ms: 100,
        request_timeout_ms: 100
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(
        enabled: true,
        endless: true,
        initial_delay_ms: 30_000,
        max_delay_ms: 30_000,
        multiplier: 1.0,
        jitter_ms: 0
      )
    )
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    wait_for_socket(path)

    client = Obsctl::IPC::UnixClient.new(path)
    reconnecting = wait_for_server_status(client) do |data|
      data["reconnecting"].as_bool && !data["last_connection_failed_at"].raw.nil?
    end
    reconnecting["obs_connected"].as_bool.should be_false
    reconnecting["last_connected_at"].raw.should be_nil
    reconnecting["last_disconnected_at"].raw.should be_nil
    parse_rfc3339(reconnecting["last_reconnect_attempt_at"])
    parse_rfc3339(reconnecting["last_connection_failed_at"])
    reconnecting["last_error"].as_s.should_not contain("OBS reconnect requested")

    obs = gate.open_fake_obs
    obs.assert_no_identify_or_connection_attempt(150.milliseconds)

    reconnect = client.request(
      Obsctl::IPC::Request.new(
        "req-wake-reconnect-backoff",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("reconnect_obs")
      )
    )
    reconnect.ok.should be_true

    identify = obs.next_identify_received(1.second) || raise "explicit reconnect did not wake OBS Identify promptly"
    identify["eventSubscriptions"].as_i.should eq(Obsctl::OBS::Protocol::EventSubscription::SERVER_DEFAULT)

    connected = wait_for_server_status(client) do |data|
      data["obs_connected"].as_bool && !data["reconnecting"].as_bool
    end
    connected["last_error"].raw.should be_nil
    parse_rfc3339(connected["last_connected_at"])
    parse_rfc3339(connected["last_reconnect_attempt_at"])
    parse_rfc3339(connected["last_connection_failed_at"])

    status = client.request(
      Obsctl::IPC::Request.new(
        "req-wake-reconnect-combined-status",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("status")
      )
    )
    status.ok.should be_true
    status.result.not_nil!["server"]["obs_connected"].as_bool.should be_true
    status.result.not_nil!["server"]["reconnecting"].as_bool.should be_false
    status.result.not_nil!["server"]["last_error"].raw.should be_nil
    status.result.not_nil!["obs"]["connected"].as_bool.should be_true
    status.result.not_nil!["obs"]["last_error"].raw.should be_nil
  ensure
    obs.try(&.stop)
    gate.try(&.release)
    server.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "reports daemon status fields through IPC" do
    path = temp_socket_path
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: 1,
        password_env: "",
        request_timeout_ms: 100
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
    )
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    wait_for_socket(path)

    subscriber = subscribe(path, ["logs"], "req-status-subscribe")
    response = Obsctl::IPC::UnixClient.new(path).request(
      Obsctl::IPC::Request.new(
        "req-server-status",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("get_server_status")
      )
    )

    response.ok.should be_true
    status = response.result.not_nil!
    status["pid"].as_i.should eq(Process.pid)
    (status["uptime_seconds"].as_i64 >= 0).should be_true
    status["socket_path"].as_s.should eq(path)
    status["client_count"].as_i.should eq(1)
    status["dropped_reconnect_diagnostic_logs"].as_i64.should eq(0)
    status["obs_connected"].as_bool.should be_false
    status["reconnecting"].as_bool.should be_false
    status.as_h.has_key?("last_connected_at").should be_true
    status.as_h.has_key?("last_disconnected_at").should be_true
    status.as_h.has_key?("last_reconnect_attempt_at").should be_true
    status.as_h.has_key?("last_connection_failed_at").should be_true
    status["last_connected_at"].raw.should be_nil
  ensure
    subscriber.try(&.close)
    server.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "executes scene commands through the server-owned OBS client" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    path = temp_socket_path
    server = Obsctl::Server::Server.new(obs.config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    until File.exists?(path)
      Fiber.yield
    end

    client = Obsctl::IPC::UnixClient.new(path)
    identify = wait_for_server_identify_data(obs)
    identify["eventSubscriptions"].as_i.should eq(Obsctl::OBS::Protocol::EventSubscription::SERVER_DEFAULT)

    response = nil
    20.times do
      response = client.request(
        Obsctl::IPC::Request.new(
          "req-scene",
          Obsctl::IPC::Request::TYPE_COMMAND,
          Obsctl::IPC::CommandPayload.new("set_scene", "screen")
        )
      )
      break if response.try(&.ok)
      sleep 50.milliseconds
    end

    response.not_nil!.ok.should be_true
    obs.current_scene.should eq("Screen Share")
  ensure
    server.try(&.stop)
    obs.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "broadcasts state changes to subscribed IPC clients" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    path = temp_socket_path
    server = Obsctl::Server::Server.new(obs.config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    until File.exists?(path)
      Fiber.yield
    end

    subscriber = Obsctl::IPC::UnixClient.new(path).connect
    subscriber.write_message(
      Obsctl::IPC::Request.new(
        "req-subscribe",
        Obsctl::IPC::Request::TYPE_SUBSCRIBE,
        nil,
        ["state"]
      )
    )

    subscriber.read_message.as(Obsctl::IPC::Response).ok.should be_true
    subscriber.read_message.as(Obsctl::IPC::Event).topic.should eq("state")

    client = Obsctl::IPC::UnixClient.new(path)
    response = nil
    20.times do
      response = client.request(
        Obsctl::IPC::Request.new(
          "req-broadcast-scene",
          Obsctl::IPC::Request::TYPE_COMMAND,
          Obsctl::IPC::CommandPayload.new("set_scene", "screen")
        )
      )
      break if response.try(&.ok)
      sleep 50.milliseconds
    end

    response.not_nil!.ok.should be_true

    event = subscriber.read_message.as(Obsctl::IPC::Event)
    event.topic.should eq("state")
    event.data.not_nil!["current_scene"].as_s.should eq("Screen Share")
  ensure
    subscriber.try(&.close)
    server.try(&.stop)
    obs.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "broadcasts OBS events to events subscribers and refreshes state subscribers" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    path = temp_socket_path
    server = Obsctl::Server::Server.new(obs.config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    until File.exists?(path)
      Fiber.yield
    end

    status_client = Obsctl::IPC::UnixClient.new(path)
    wait_for_obs_connected(status_client)

    events = subscribe(path, ["events"], "req-events")
    state = subscribe(path, ["state"], "req-state")
    state.read_message.as(Obsctl::IPC::Event).topic.should eq("state")

    obs.emit_current_scene_changed("Screen Share")

    event = read_ipc_message(events).as(Obsctl::IPC::Event)
    event.topic.should eq("events")
    event.data.not_nil!["event_type"].as_s.should eq("CurrentProgramSceneChanged")
    event.data.not_nil!["event_data"]["sceneName"].as_s.should eq("Screen Share")

    state_event = read_ipc_message(state).as(Obsctl::IPC::Event)
    state_event.topic.should eq("state")
    state_event.data.not_nil!["current_scene"].as_s.should eq("Screen Share")
  ensure
    events.try(&.close)
    state.try(&.close)
    server.try(&.stop)
    obs.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "broadcasts command failure logs to logs subscribers" do
    path = temp_socket_path
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: 1,
        password_env: "",
        request_timeout_ms: 100,
        reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
      ),
      scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera", "main"),
      ]
    )
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    until File.exists?(path)
      Fiber.yield
    end

    logs = subscribe(path, ["logs"], "req-logs")
    client = Obsctl::IPC::UnixClient.new(path)
    response = client.request(
      Obsctl::IPC::Request.new(
        "req-missing-obs",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("set_scene", "main")
      )
    )

    response.ok.should be_false
    response.error.not_nil!.code.should eq("OBS_UNAVAILABLE")

    log = read_ipc_message(logs).as(Obsctl::IPC::Event)
    log.topic.should eq("logs")
    log.data.not_nil!["level"].as_s.should eq("warn")
    log.data.not_nil!["code"].as_s.should eq("command_failed")
    log.data.not_nil!["message"].as_s.should contain("OBS")
  ensure
    logs.try(&.close)
    server.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "persists server log events through the configured runtime logger" do
    path = temp_socket_path
    log_path = File.join(Dir.tempdir, "obsctl-server-log-spec-#{Random.rand(1_000_000)}.log")
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: 1,
        password_env: "",
        request_timeout_ms: 100
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false),
      scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera", "main"),
      ]
    )
    logger = Obsctl::Runtime::Logger.new(Obsctl::Runtime::LogLevel::Warn, log_path)
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path, logger: logger)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    wait_for_socket(path)

    response = Obsctl::IPC::UnixClient.new(path).request(
      Obsctl::IPC::Request.new(
        "req-log-failure",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("set_scene", "main")
      )
    )

    response.ok.should be_false
    log = File.read(log_path)
    log.should contain("level=warn")
    log.should contain("command_failed")
    log.should contain("OBS")
    log.should_not contain("server_start")
  ensure
    server.try(&.stop)
    File.delete(path) if path && File.exists?(path)
    File.delete(log_path) if log_path && File.exists?(log_path)
  end

  it "marks OBS disconnected after an established WebSocket closes while IPC stays available" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    path = temp_socket_path
    server = Obsctl::Server::Server.new(obs.config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    until File.exists?(path)
      Fiber.yield
    end

    client = Obsctl::IPC::UnixClient.new(path)
    wait_for_obs_connected(client)
    logs = subscribe(path, ["logs"], "req-passive-disconnect-logs")

    obs.stop
    status = wait_for_obs_disconnected(client)

    status["connected"].as_bool.should be_false
    status["last_error"].as_s.should contain("OBS WebSocket disconnected")

    daemon_status = wait_for_server_status(client) do |data|
      !data["last_disconnected_at"].raw.nil?
    end
    daemon_status["obs_connected"].as_bool.should be_false
    parse_rfc3339(daemon_status["last_connected_at"])
    parse_rfc3339(daemon_status["last_disconnected_at"])
    daemon_status["last_connection_failed_at"].raw.should be_nil
    daemon_status["last_error"].as_s.should contain("OBS WebSocket disconnected")

    log = read_log_until(logs, "obs_disconnected")
    log["message"].as_s.should contain("OBS WebSocket disconnected")

    response = client.request(
      Obsctl::IPC::Request.new(
        "req-scene-after-close",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("set_scene", "screen")
      )
    )
    response.ok.should be_false
    response.error.not_nil!.code.should eq("OBS_UNAVAILABLE")
  ensure
    logs.try(&.close)
    server.try(&.stop)
    obs.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "keeps reconnect requests as the public state until reconnect succeeds" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    base_config = obs.config
    config = Obsctl::Config::Config.new(
      connection: base_config.connection,
      reconnect: Obsctl::Config::ReconnectConfig.new(
        enabled: true,
        endless: true,
        initial_delay_ms: 50,
        max_delay_ms: 50,
        multiplier: 1.0,
        jitter_ms: 0
      ),
      scenes: base_config.scenes,
      audio: base_config.audio
    )
    path = temp_socket_path
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    wait_for_socket(path)
    connection_id = next_server_spec_websocket_connection_id(obs)

    state = subscribe(path, ["state", "logs"], "req-clean-close-state")
    connected = read_state_until(state, connected: true)
    connected["connected"].as_bool.should be_true

    response = Obsctl::IPC::UnixClient.new(path).request(
      Obsctl::IPC::Request.new(
        "req-clean-close-reconnect",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("reconnect_obs")
      )
    )
    response.ok.should be_true
    obs.assert_websocket_connection_closed(connection_id, 2.seconds)

    disconnected = read_state_error_until(state, "OBS reconnect requested")
    disconnected["connected"].as_bool.should be_false
    disconnected["last_error"].as_s.should eq("OBS reconnect requested")

    log = read_log_until(state, "obs_reconnect_requested")
    log["message"].as_s.should eq("OBS reconnect requested")

    obs.next_identify(3.seconds).should_not be_nil
    reconnected = read_state_until_reconnected_without_clean_close(state)
    reconnected["connected"].as_bool.should be_true
    reconnected["last_error"].raw.should be_nil

    status = Obsctl::IPC::UnixClient.new(path).request(
      Obsctl::IPC::Request.new(
        "req-server-status-reconnect-success",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("get_server_status")
      )
    )
    status.ok.should be_true
    status.result.not_nil!["obs_connected"].as_bool.should be_true
    status.result.not_nil!["reconnecting"].as_bool.should be_false
    parse_rfc3339(status.result.not_nil!["last_connected_at"])
    parse_rfc3339(status.result.not_nil!["last_disconnected_at"])
    parse_rfc3339(status.result.not_nil!["last_reconnect_attempt_at"])
    status.result.not_nil!["last_connection_failed_at"].raw.should be_nil
    status.result.not_nil!["last_error"].raw.should be_nil
  ensure
    state.try(&.close)
    server.try(&.stop)
    obs.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "reports malformed OBS frames in state, server status, and logs" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    base_config = obs.config
    config = Obsctl::Config::Config.new(
      connection: base_config.connection,
      reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false),
      scenes: base_config.scenes,
      audio: base_config.audio
    )
    path = temp_socket_path
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    wait_for_socket(path)
    connection_id = next_server_spec_websocket_connection_id(obs)

    state = subscribe(path, ["state", "logs"], "req-malformed-frame-state")
    connected = read_state_until(state, connected: true)
    connected["connected"].as_bool.should be_true

    obs.emit_raw_frame("{not-json")
    obs.assert_websocket_connection_closed(connection_id, 2.seconds)

    disconnected = read_state_until(state, connected: false)
    disconnected["connected"].as_bool.should be_false
    disconnected["last_error"].as_s.should contain("malformed OBS frame")
    disconnected["last_error"].as_s.should_not contain("password")
    disconnected["last_error"].as_s.should_not contain("secret")

    log = read_log_until(state, "obs_malformed_frame")
    log["message"].as_s.should contain("malformed OBS frame")

    status = Obsctl::IPC::UnixClient.new(path).request(
      Obsctl::IPC::Request.new(
        "req-server-status-malformed-frame",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("get_server_status")
      )
    )
    status.ok.should be_true
    status.result.not_nil!["obs_connected"].as_bool.should be_false
    parse_rfc3339(status.result.not_nil!["last_connected_at"])
    parse_rfc3339(status.result.not_nil!["last_disconnected_at"])
    parse_rfc3339(status.result.not_nil!["last_reconnect_attempt_at"])
    status.result.not_nil!["last_connection_failed_at"].raw.should be_nil
    status.result.not_nil!["last_error"].as_s.should contain("malformed OBS frame")
  ensure
    state.try(&.close)
    server.try(&.stop)
    obs.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "reconnects after protocol-error client close while IPC stays available" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    base_config = obs.config
    config = Obsctl::Config::Config.new(
      connection: base_config.connection,
      reconnect: Obsctl::Config::ReconnectConfig.new(
        enabled: true,
        endless: true,
        initial_delay_ms: 500,
        max_delay_ms: 500,
        multiplier: 1.0,
        jitter_ms: 0
      ),
      scenes: base_config.scenes,
      audio: base_config.audio
    )
    path = temp_socket_path
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    wait_for_socket(path)

    first_connection_id = next_server_spec_websocket_connection_id(obs)
    first_identify = obs.next_identify(2.seconds) || raise "fake OBS did not receive initial Identify"
    first_identify["eventSubscriptions"].as_i.should eq(Obsctl::OBS::Protocol::EventSubscription::SERVER_DEFAULT)

    state = subscribe(path, ["state", "logs"], "req-protocol-error-state")
    connected = read_state_until(state, connected: true)
    connected["connected"].as_bool.should be_true

    obs.emit_raw_frame(%({"op":7,"d":{"requestType":"GetVersion"}}))
    obs.assert_websocket_connection_closed(first_connection_id, 2.seconds)

    disconnected = read_state_until(state, connected: false)
    disconnected["connected"].as_bool.should be_false
    disconnected["last_error"].as_s.should contain("response parser error")

    log = read_log_until(state, "obs_response_parser_error")
    log["message"].as_s.should contain("response parser error")

    ipc = Obsctl::IPC::UnixClient.new(path)
    status = ipc.request(
      Obsctl::IPC::Request.new(
        "req-server-status-protocol-gap",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("get_server_status")
      )
    )
    status.ok.should be_true
    status.result.not_nil!["obs_connected"].as_bool.should be_false
    status.result.not_nil!["reconnecting"].as_bool.should be_true
    parse_rfc3339(status.result.not_nil!["last_connected_at"])
    parse_rfc3339(status.result.not_nil!["last_disconnected_at"])
    parse_rfc3339(status.result.not_nil!["last_reconnect_attempt_at"])
    status.result.not_nil!["last_connection_failed_at"].raw.should be_nil
    status.result.not_nil!["last_error"].as_s.should contain("response parser error")

    scene_response = ipc.request(
      Obsctl::IPC::Request.new(
        "req-scene-protocol-gap",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("set_scene", "screen")
      )
    )
    scene_response.ok.should be_false
    scene_response.error.not_nil!.code.should eq(Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE)

    mute_response = ipc.request(
      Obsctl::IPC::Request.new(
        "req-mute-protocol-gap",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("mute", "mic")
      )
    )
    mute_response.ok.should be_false
    mute_response.error.not_nil!.code.should eq(Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE)

    obs.next_identify(3.seconds).should_not be_nil
    reconnected = read_state_until(state, connected: true)
    reconnected["connected"].as_bool.should be_true

    recovered = ipc.request(
      Obsctl::IPC::Request.new(
        "req-scene-after-protocol-reconnect",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("set_scene", "screen")
      )
    )
    recovered.ok.should be_true
    obs.current_scene.should eq("Screen Share")
  ensure
    state.try(&.close)
    server.try(&.stop)
    obs.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "validates config through IPC without connecting clients directly to OBS" do
    path = temp_socket_path
    config_path = File.join(Dir.tempdir, "obsctl-server-validate-#{Random.rand(1_000_000)}.yml")
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: 1,
        password_env: "",
        request_timeout_ms: 100
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
    )
    Obsctl::Config::ConfigWriter.new.write(config_path, config)
    server = Obsctl::Server::Server.new(config, config_path, socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    wait_for_socket(path)

    response = Obsctl::IPC::UnixClient.new(path).request(
      Obsctl::IPC::Request.new(
        "req-validate",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("validate_config")
      )
    )

    response.ok.should be_true
    response.result.not_nil!["message"].as_s.should contain("config valid")
  ensure
    server.try(&.stop)
    File.delete(path) if path && File.exists?(path)
    File.delete(config_path) if config_path && File.exists?(config_path)
  end

  it "keeps remote shutdown disabled by default" do
    path = temp_socket_path
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: 1,
        password_env: "",
        request_timeout_ms: 100
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
    )
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
    end

    ready.receive
    wait_for_socket(path)

    response = Obsctl::IPC::UnixClient.new(path).request(
      Obsctl::IPC::Request.new(
        "req-shutdown-disabled",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("shutdown_server")
      )
    )

    response.ok.should be_false
    response.error.not_nil!.code.should eq("SHUTDOWN_DISABLED")
    File.exists?(path).should be_true
  ensure
    server.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end

  it "honors explicitly enabled remote shutdown after responding" do
    path = temp_socket_path
    config = Obsctl::Config::Config.new(
      server: Obsctl::Config::ServerConfig.new(allow_remote_shutdown: true),
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: 1,
        password_env: "",
        request_timeout_ms: 100
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
    )
    server = Obsctl::Server::Server.new(config, "/tmp/obsctl-server-spec.yml", socket_path: path)
    ready = Channel(Nil).new
    stopped = Channel(Nil).new

    spawn do
      ready.send(nil)
      server.run
      stopped.send(nil)
    end

    ready.receive
    wait_for_socket(path)

    response = Obsctl::IPC::UnixClient.new(path).request(
      Obsctl::IPC::Request.new(
        "req-shutdown-enabled",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("shutdown_server")
      )
    )

    response.ok.should be_true
    response.result.not_nil!["message"].as_s.should contain("shutdown requested")

    select
    when stopped.receive
    when timeout(2.seconds)
      raise "server did not stop after shutdown request"
    end
    File.exists?(path).should be_false
  ensure
    server.try(&.stop)
    File.delete(path) if path && File.exists?(path)
  end
end

private def subscribe(path : String, topics : Array(String), id : String) : Obsctl::IPC::ClientSession
  session = Obsctl::IPC::UnixClient.new(path).connect
  session.write_message(
    Obsctl::IPC::Request.new(
      id,
      Obsctl::IPC::Request::TYPE_SUBSCRIBE,
      nil,
      topics
    )
  )
  session.read_message.as(Obsctl::IPC::Response).ok.should be_true
  session
end

private def read_ipc_message(session : Obsctl::IPC::ClientSession, timeout : Time::Span = 2.seconds) : Obsctl::IPC::Message
  messages = Channel(Obsctl::IPC::Message?).new(1)
  spawn { messages.send(session.read_message) }
  select
  when message = messages.receive
    message || raise "IPC session closed before expected message"
  when timeout(timeout)
    raise "timed out waiting for IPC message"
  end
end

private def wait_for_server_identify_data(server : Obsctl::SpecSupport::FakeObsServer) : JSON::Any
  20.times do
    if data = server.identify_data
      return data
    end
    sleep 50.milliseconds
  end

  raise "fake OBS server did not receive Identify data"
end

private def wait_for_obs_connected(client : Obsctl::IPC::UnixClient) : JSON::Any
  wait_for_obs_status(client, connected: true)
end

private def wait_for_obs_disconnected(client : Obsctl::IPC::UnixClient) : JSON::Any
  wait_for_obs_status(client, connected: false)
end

private def wait_for_server_status(
  client : Obsctl::IPC::UnixClient,
  timeout : Time::Span = 3.seconds,
  &block : JSON::Any -> Bool
) : JSON::Any
  deadline = Time.instant + timeout

  loop do
    remaining = deadline - Time.instant
    raise "timed out waiting for matching server status" if remaining <= 0.seconds

    response = client.request(
      Obsctl::IPC::Request.new(
        "req-server-status-wait",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("get_server_status")
      )
    )
    response.ok.should be_true
    status = response.result.not_nil!
    return status if yield status
    sleep(remaining < 50.milliseconds ? remaining : 50.milliseconds)
  end
end

private def parse_rfc3339(value : JSON::Any) : Time
  Time.parse_rfc3339(value.as_s)
end

private def wait_for_obs_status(client : Obsctl::IPC::UnixClient, connected : Bool) : JSON::Any
  40.times do
    response = client.request(
      Obsctl::IPC::Request.new(
        "req-status-#{connected}",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("get_obs_status")
      )
    )
    response.ok.should be_true
    status = response.result.not_nil!
    return status if status["connected"].as_bool == connected
    sleep 50.milliseconds
  end

  raise "server did not report OBS connected=#{connected}"
end

private def wait_for_socket(path : String) : Nil
  40.times do
    return if File.exists?(path)
    sleep 25.milliseconds
  end

  raise "server socket was not created: #{path}"
end

private def read_state_until(session : Obsctl::IPC::ClientSession, connected : Bool, timeout : Time::Span = 3.seconds) : JSON::Any
  deadline = Time.instant + timeout

  loop do
    remaining = deadline - Time.instant
    raise "timed out waiting for state connected=#{connected}" if remaining <= 0.seconds

    message = read_ipc_message(session, remaining)
    next unless event = message.as?(Obsctl::IPC::Event)
    next unless event.topic == "state"

    data = event.data.not_nil!
    return data if data["connected"].as_bool == connected
  end
end

private def read_state_error_until(session : Obsctl::IPC::ClientSession, error_text : String, timeout : Time::Span = 3.seconds) : JSON::Any
  deadline = Time.instant + timeout

  loop do
    remaining = deadline - Time.instant
    raise "timed out waiting for state last_error containing #{error_text}" if remaining <= 0.seconds

    message = read_ipc_message(session, remaining)
    next unless event = message.as?(Obsctl::IPC::Event)
    next unless event.topic == "state"

    data = event.data.not_nil!
    return data if data["last_error"]?.try(&.as_s?).try(&.includes?(error_text))
  end
end

private def read_state_until_reconnected_without_clean_close(
  session : Obsctl::IPC::ClientSession,
  timeout : Time::Span = 3.seconds,
) : JSON::Any
  deadline = Time.instant + timeout

  loop do
    remaining = deadline - Time.instant
    raise "timed out waiting for reconnect success" if remaining <= 0.seconds

    message = read_ipc_message(session, remaining)
    next unless event = message.as?(Obsctl::IPC::Event)
    next unless event.topic == "state"

    data = event.data.not_nil!
    error = data["last_error"]?.try(&.as_s?)
    raise "reconnect close overwrote requested state: #{error}" if error.try(&.includes?("closed cleanly"))
    return data if data["connected"].as_bool && error.nil?
  end
end

private def read_log_until(session : Obsctl::IPC::ClientSession, code : String, timeout : Time::Span = 3.seconds) : JSON::Any
  deadline = Time.instant + timeout

  loop do
    remaining = deadline - Time.instant
    raise "timed out waiting for log code=#{code}" if remaining <= 0.seconds

    message = read_ipc_message(session, remaining)
    next unless event = message.as?(Obsctl::IPC::Event)
    next unless event.topic == "logs"

    data = event.data.not_nil!
    return data if data["code"].as_s == code
  end
end
