require "../../spec_helper"
require "../../../src/obsctl/server/obs_supervisor"
require "../../support/fake_obs_server"

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
end
