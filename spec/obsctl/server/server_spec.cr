require "../../spec_helper"
require "../../../src/obsctl/server/server"
require "../../../src/obsctl/ipc/protocol"
require "../../../src/obsctl/obs/protocol/event_subscription"
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
