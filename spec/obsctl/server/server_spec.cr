require "../../spec_helper"
require "../../../src/obsctl/server/server"
require "../../../src/obsctl/ipc/protocol"
require "../../../src/obsctl/obs/protocol/event_subscription"
require "../../../src/obsctl/runtime/logger"
require "../../support/fake_obs_server"

private def temp_socket_path : String
  File.join(Dir.tempdir, "obsctl-server-spec-#{Random.rand(1_000_000)}.sock")
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
  ensure
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

    obs.stop
    status = wait_for_obs_disconnected(client)

    status["connected"].as_bool.should be_false
    status["last_error"].as_s.should contain("OBS WebSocket closed")

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
