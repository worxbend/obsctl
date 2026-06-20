require "../../spec_helper"
require "socket"
require "../../../src/obsctl/server/obs_supervisor"
require "../../support/fake_obs_server"

private def unused_tcp_port : Int32
  server = nil.as(TCPServer?)
  server = TCPServer.new("127.0.0.1", 0)
  server.local_address.port
ensure
  server.try(&.close)
end

private def wait_for_supervisor(timeout : Time::Span = 3.seconds, &block : -> Bool) : Nil
  deadline = Time.instant + timeout

  until block.call
    raise "timed out waiting for supervisor condition" if Time.instant >= deadline
    Fiber.yield
  end
end

describe Obsctl::Server::ObsSupervisor do
  it "reports alive while the supervisor loop is running" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(obs.config, state)

    supervisor.start
    supervisor.alive?.should be_true
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { supervisor.alive? && state.snapshot.connected }

    supervisor.alive?.should be_true
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "reports not alive after startup failure exits with reconnect disabled" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: 1,
        password_env: "",
        request_timeout_ms: 100
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
    )
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(config, state)

    supervisor.start
    wait_for_supervisor do
      !state.telemetry.last_connection_failed_at.nil? && !supervisor.alive?
    end

    supervisor.alive?.should be_false
  ensure
    supervisor.try(&.stop)
  end

  it "reports not alive immediately after stop" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(obs.config, state)

    supervisor.start
    supervisor.alive?.should be_true

    supervisor.stop

    supervisor.alive?.should be_false
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
  end

  it "ignores double start calls while already alive" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(obs.config, state)

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }

    supervisor.start

    obs.assert_no_identify_or_connection_attempt(150.milliseconds)
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "keeps OBS ownership scoped after stop followed by immediate start" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(obs.config, state)

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }
    obs.identify_count.should eq(1)

    supervisor.stop
    supervisor.start

    obs.next_close(2.seconds).should be_true
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor do
      begin
        supervisor.with_client { true }
      rescue Obsctl::Domain::ObsUnavailable
        false
      end
    end

    obs.connection_attempt_count.should eq(2)
    obs.identify_count.should eq(2)
    obs.assert_no_identify_or_connection_attempt(600.milliseconds)
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "wakes retry backoff when reconnect is requested" do
    obs = nil.as(Obsctl::SpecSupport::FakeObsServer?)
    obs_port = unused_tcp_port
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        host: "127.0.0.1",
        port: obs_port,
        password_env: "",
        connect_timeout_ms: 100,
        request_timeout_ms: 100
      ),
      reconnect: Obsctl::Config::ReconnectConfig.new(
        enabled: true,
        endless: true,
        initial_delay_ms: 5_000,
        max_delay_ms: 5_000,
        multiplier: 1.0,
        jitter_ms: 0
      )
    )
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(config, state)

    supervisor.start
    wait_for_supervisor do
      supervisor.alive? &&
        state.telemetry.reconnecting &&
        !state.telemetry.last_connection_failed_at.nil?
    end

    obs = Obsctl::SpecSupport::FakeObsServer.new(port: obs_port).start
    obs.assert_no_identify_or_connection_attempt(150.milliseconds)

    supervisor.reconnect.should be_true

    obs.next_identify(1.second).should_not be_nil
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "does not let a reconnect wake from an active close skip the next retry delay" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    base_config = obs.config
    config = Obsctl::Config::Config.new(
      connection: base_config.connection,
      reconnect: Obsctl::Config::ReconnectConfig.new(
        enabled: true,
        endless: true,
        initial_delay_ms: 5_000,
        max_delay_ms: 5_000,
        multiplier: 1.0,
        jitter_ms: 0
      ),
      scenes: base_config.scenes,
      audio: base_config.audio
    )
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(config, state)

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }

    supervisor.reconnect.should be_true
    obs.next_close_observed(2.seconds).should be_true
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }

    connection_attempts_after_explicit_reconnect = obs.connection_attempt_count
    identifies_after_explicit_reconnect = obs.identify_count

    obs.close_connections
    obs.next_close_observed(2.seconds).should be_true
    wait_for_supervisor { !state.snapshot.connected && state.telemetry.reconnecting }

    obs.assert_no_identify_or_connection_attempt(150.milliseconds)
    obs.connection_attempt_count.should eq(connection_attempts_after_explicit_reconnect)
    obs.identify_count.should eq(identifies_after_explicit_reconnect)

    supervisor.reconnect.should be_true
    obs.next_identify(1.second).should_not be_nil
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end
end
