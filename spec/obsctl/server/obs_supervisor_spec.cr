require "../../spec_helper"
require "../../../src/obsctl/server/obs_supervisor"
require "../../support/fake_obs_server"
require "../../support/tcp_gate"

private def wait_for_supervisor(timeout : Time::Span = 3.seconds, &block : -> Bool) : Nil
  deadline = Time.instant + timeout

  until block.call
    raise "timed out waiting for supervisor condition" if Time.instant >= deadline
    Fiber.yield
  end
end

private class FailedAttemptBeforeDelayStateStore < Obsctl::Server::StateStore
  def initialize
    super()
    @gate_lock = Mutex.new
    @blocked = false
    @released = false
    @failed_attempt_before_delay = Channel(Nil).new(1)
    @release_failed_attempt = Channel(Nil).new(1)
  end

  def mark_disconnected(
    error : String? = nil,
    reconnecting : Bool = false,
    at : Time = Time.utc,
    connection_failed : Bool = true,
  ) : Nil
    should_block = false
    was_connected = snapshot.connected
    @gate_lock.synchronize do
      should_block = !@blocked && !was_connected && reconnecting && connection_failed
      @blocked = true if should_block
    end

    super

    return unless should_block

    select
    when @failed_attempt_before_delay.send(nil)
    else
    end
    @release_failed_attempt.receive
  end

  def wait_for_failed_attempt_before_delay(timeout : Time::Span = 1.second) : Bool
    select
    when @failed_attempt_before_delay.receive
      true
    when timeout(timeout)
      false
    end
  end

  def release_failed_attempt : Nil
    should_release = @gate_lock.synchronize do
      next false unless @blocked && !@released

      @released = true
      true
    end
    return unless should_release

    select
    when @release_failed_attempt.send(nil)
    else
    end
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
    gate = Obsctl::SpecSupport::TcpGate.new
    obs = nil.as(Obsctl::SpecSupport::FakeObsServer?)
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

    obs = gate.open_fake_obs
    obs.assert_no_identify_or_connection_attempt(150.milliseconds)

    supervisor.reconnect.should be_true

    obs.next_identify(1.second).should_not be_nil
  ensure
    gate.try(&.release)
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "preserves an explicit reconnect request made after failure before retry delay starts" do
    gate = Obsctl::SpecSupport::TcpGate.new
    obs = nil.as(Obsctl::SpecSupport::FakeObsServer?)
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
        initial_delay_ms: 5_000,
        max_delay_ms: 5_000,
        multiplier: 1.0,
        jitter_ms: 0
      )
    )
    state = FailedAttemptBeforeDelayStateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(config, state)

    supervisor.start
    state.wait_for_failed_attempt_before_delay(2.seconds).should be_true

    supervisor.reconnect.should be_true
    obs = gate.open_fake_obs
    state.release_failed_attempt

    obs.next_identify_received(1.second).should_not be_nil
  ensure
    gate.try(&.release)
    state.try(&.release_failed_attempt)
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "rejects reconnect when stop wins after reconnect observes a live generation" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    state_updates = [] of JSON::Any
    state_update_lock = Mutex.new
    event_updates = [] of JSON::Any
    event_update_lock = Mutex.new
    log_updates = [] of JSON::Any
    log_update_lock = Mutex.new
    state = Obsctl::Server::StateStore.new(->(payload : JSON::Any) {
      state_update_lock.synchronize { state_updates << payload }
    })
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      ->(payload : JSON::Any) { event_update_lock.synchronize { event_updates << payload } },
      ->(payload : JSON::Any) { log_update_lock.synchronize { log_updates << payload } }
    )
    reconnect_paused = Channel(Nil).new(1)
    release_reconnect = Channel(Nil).new(1)
    reconnect_result = Channel(Bool).new(1)

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor do
      state.snapshot.connected &&
        log_update_lock.synchronize do
          log_updates.any? { |payload| payload["code"].as_s == "obs_connected" }
        end
    end

    state_update_lock.synchronize { state_updates.clear }
    event_update_lock.synchronize { event_updates.clear }
    log_update_lock.synchronize { log_updates.clear }

    supervisor.test_reconnect_before_publication = -> {
      select
      when reconnect_paused.send(nil)
      else
      end
      release_reconnect.receive
    }

    spawn(name: "obs-supervisor-reconnect-vs-stop-spec") do
      reconnect_result.send(supervisor.reconnect)
    end

    select
    when reconnect_paused.receive
    when timeout(2.seconds)
      raise "reconnect did not pause after observing a live generation"
    end

    supervisor.stop
    supervisor.alive?.should be_false
    obs.next_close_observed(2.seconds).should be_true
    close_count_after_stop = obs.close_count
    snapshot_after_stop = state.snapshot
    telemetry_after_stop = state.telemetry

    release_reconnect.send(nil)
    result = select
    when accepted = reconnect_result.receive
      accepted
    when timeout(2.seconds)
      raise "reconnect did not finish after stop completed"
    end

    result.should be_false
    supervisor.stopped_reconnect_attempted?.should be_true
    obs.close_count.should eq(close_count_after_stop)
    state.snapshot.should eq(snapshot_after_stop)
    state.telemetry.should eq(telemetry_after_stop)
    state.snapshot.last_error.should_not eq("OBS reconnect requested")
    state_update_lock.synchronize { state_updates.dup }.should be_empty
    event_update_lock.synchronize { event_updates.dup }.should be_empty
    logs_after_reconnect = log_update_lock.synchronize { log_updates.dup }
    logs_after_reconnect.should be_empty
    logs_after_reconnect.any? do |payload|
      payload["code"].as_s == "obs_reconnect_requested" ||
        payload["message"].as_s == "OBS reconnect requested"
    end.should be_false
  ensure
    supervisor.try { |instance| instance.test_reconnect_before_publication = nil }
    if release = release_reconnect
      select
      when release.send(nil)
      else
      end
    end
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "stops promptly while accepted reconnect publication fanout is blocked" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    block_reconnect_publication = false
    block_lock = Mutex.new
    publication_blocked = Channel(Nil).new(1)
    release_publication = Channel(Nil).new(1)
    state = Obsctl::Server::StateStore.new(->(payload : JSON::Any) {
      should_block = block_lock.synchronize do
        block_reconnect_publication && payload["last_error"]?.try(&.as_s?) == "OBS reconnect requested"
      end

      if should_block
        select
        when publication_blocked.send(nil)
        else
        end
        release_publication.receive
      end
    })
    supervisor = Obsctl::Server::ObsSupervisor.new(obs.config, state)
    reconnect_result = Channel(Bool).new(1)
    stop_finished = Channel(Nil).new(1)

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }

    block_lock.synchronize { block_reconnect_publication = true }
    spawn(name: "obs-supervisor-blocked-reconnect-publication-spec") do
      reconnect_result.send(supervisor.reconnect)
    end

    select
    when publication_blocked.receive
    when timeout(2.seconds)
      raise "reconnect publication did not reach blocking state callback"
    end

    obs.next_close_observed(2.seconds).should be_true

    spawn(name: "obs-supervisor-stop-during-blocked-publication-spec") do
      supervisor.stop
      stop_finished.send(nil)
    end

    select
    when stop_finished.receive
    when timeout(250.milliseconds)
      raise "supervisor stop was blocked by reconnect publication fanout"
    end

    supervisor.alive?.should be_false
    select
    when reconnect_result.receive
      raise "reconnect finished before blocked publication was released"
    when timeout(50.milliseconds)
    end

    release_publication.send(nil)
    result = select
    when accepted = reconnect_result.receive
      accepted
    when timeout(2.seconds)
      raise "reconnect did not finish after publication was released"
    end
    result.should be_true
  ensure
    if release = release_publication
      select
      when release.send(nil)
      else
      end
    end
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "stops promptly while accepted reconnect log fanout is blocked" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    block_reconnect_log = false
    block_lock = Mutex.new
    log_blocked = Channel(Nil).new(1)
    release_log = Channel(Nil).new(1)
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      ->(payload : JSON::Any) {
        should_block = block_lock.synchronize do
          block_reconnect_log && payload["code"]?.try(&.as_s?) == "obs_reconnect_requested"
        end

        if should_block
          select
          when log_blocked.send(nil)
          else
          end
          release_log.receive
        end
      }
    )
    reconnect_result = Channel(Bool).new(1)
    stop_finished = Channel(Nil).new(1)

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }

    block_lock.synchronize { block_reconnect_log = true }
    spawn(name: "obs-supervisor-blocked-reconnect-log-publication-spec") do
      reconnect_result.send(supervisor.reconnect)
    end

    select
    when log_blocked.receive
    when timeout(2.seconds)
      raise "reconnect publication did not reach blocking log callback"
    end

    obs.next_close_observed(2.seconds).should be_true

    spawn(name: "obs-supervisor-stop-during-blocked-log-publication-spec") do
      supervisor.stop
      stop_finished.send(nil)
    end

    select
    when stop_finished.receive
    when timeout(250.milliseconds)
      raise "supervisor stop was blocked by reconnect log fanout"
    end

    supervisor.alive?.should be_false
    select
    when reconnect_result.receive
      raise "reconnect finished before blocked log publication was released"
    when timeout(50.milliseconds)
    end

    release_log.send(nil)
    result = select
    when accepted = reconnect_result.receive
      accepted
    when timeout(2.seconds)
      raise "reconnect did not finish after log publication was released"
    end
    result.should be_true
  ensure
    if release = release_log
      select
      when release.send(nil)
      else
      end
    end
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "returns success and records a sanitized diagnostic when reconnect state publication raises" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    log_updates = [] of JSON::Any
    log_update_lock = Mutex.new
    state = Obsctl::Server::StateStore.new(->(payload : JSON::Any) {
      if payload["last_error"]?.try(&.as_s?) == "OBS reconnect requested"
        raise "state publication failed password=supersecret token: abc123"
      end
    })
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      ->(payload : JSON::Any) { log_update_lock.synchronize { log_updates << payload } }
    )

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }
    log_update_lock.synchronize { log_updates.clear }

    supervisor.reconnect.should be_true
    obs.next_close_observed(2.seconds).should be_true
    state.snapshot.last_error.should eq("OBS reconnect requested")

    logs_after_reconnect = log_update_lock.synchronize { log_updates.dup }
    diagnostic = logs_after_reconnect.find do |payload|
      payload["code"].as_s == "obs_reconnect_state_publication_failed"
    end
    diagnostic.should_not be_nil
    message = diagnostic.not_nil!["message"].as_s
    message.should contain("OBS reconnect state publication failed")
    message.should contain("[redacted]")
    message.should_not contain("supersecret")
    message.should_not contain("abc123")
    logs_after_reconnect.each do |payload|
      payload["message"].as_s.should_not contain("supersecret")
      payload["message"].as_s.should_not contain("abc123")
    end
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "returns success while reconnect state publication diagnostic log fanout is blocked" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    block_diagnostic = false
    block_lock = Mutex.new
    diagnostic_blocked = Channel(Nil).new(1)
    release_diagnostic = Channel(Nil).new(1)
    state = Obsctl::Server::StateStore.new(->(payload : JSON::Any) {
      if payload["last_error"]?.try(&.as_s?) == "OBS reconnect requested"
        raise "state publication failed password=supersecret token: abc123"
      end
    })
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      ->(payload : JSON::Any) {
        should_block = block_lock.synchronize do
          block_diagnostic && payload["code"]?.try(&.as_s?) == "obs_reconnect_state_publication_failed"
        end

        if should_block
          select
          when diagnostic_blocked.send(nil)
          else
          end
          release_diagnostic.receive
        end
      }
    )
    reconnect_result = Channel(Bool).new(1)

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }

    block_lock.synchronize { block_diagnostic = true }
    spawn(name: "obs-supervisor-blocked-state-diagnostic-publication-spec") do
      reconnect_result.send(supervisor.reconnect)
    end

    obs.next_close_observed(2.seconds).should be_true

    select
    when diagnostic_blocked.receive
    when timeout(2.seconds)
      raise "state publication diagnostic did not reach blocking log callback"
    end

    result = select
    when accepted = reconnect_result.receive
      accepted
    when timeout(2.seconds)
      raise "reconnect did not finish while diagnostic log fanout was blocked"
    end
    result.should be_true
    state.snapshot.last_error.should eq("OBS reconnect requested")
  ensure
    if release = release_diagnostic
      select
      when release.send(nil)
      else
      end
    end
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "returns success and records a sanitized diagnostic when reconnect log publication raises" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    log_updates = [] of JSON::Any
    log_update_lock = Mutex.new
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      ->(payload : JSON::Any) {
        if payload["code"]?.try(&.as_s?) == "obs_reconnect_requested"
          raise "log publication failed authentication string is generated-token secret: abc123"
        end
        log_update_lock.synchronize { log_updates << payload }
      }
    )

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }
    log_update_lock.synchronize { log_updates.clear }

    supervisor.reconnect.should be_true
    obs.next_close_observed(2.seconds).should be_true
    state.snapshot.last_error.should eq("OBS reconnect requested")

    logs_after_reconnect = log_update_lock.synchronize { log_updates.dup }
    diagnostic = logs_after_reconnect.find do |payload|
      payload["code"].as_s == "obs_reconnect_log_publication_failed"
    end
    diagnostic.should_not be_nil
    message = diagnostic.not_nil!["message"].as_s
    message.should contain("OBS reconnect log publication failed")
    message.should contain("[redacted]")
    message.should_not contain("generated-token")
    message.should_not contain("abc123")
    logs_after_reconnect.each do |payload|
      payload["message"].as_s.should_not contain("generated-token")
      payload["message"].as_s.should_not contain("abc123")
    end
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "returns success while reconnect log publication diagnostic log fanout is blocked" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    block_reconnect_log = false
    block_lock = Mutex.new
    diagnostic_blocked = Channel(Nil).new(1)
    release_diagnostic = Channel(Nil).new(1)
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      ->(payload : JSON::Any) {
        code = payload["code"]?.try(&.as_s?)
        should_block = block_lock.synchronize do
          block_reconnect_log && code == "obs_reconnect_log_publication_failed"
        end

        if should_block
          select
          when diagnostic_blocked.send(nil)
          else
          end
          release_diagnostic.receive
        elsif block_lock.synchronize { block_reconnect_log } && code == "obs_reconnect_requested"
          raise "log publication failed authentication string is generated-token secret: abc123"
        end
      }
    )
    reconnect_result = Channel(Bool).new(1)

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }

    block_lock.synchronize { block_reconnect_log = true }
    spawn(name: "obs-supervisor-blocked-log-diagnostic-publication-spec") do
      reconnect_result.send(supervisor.reconnect)
    end

    obs.next_close_observed(2.seconds).should be_true

    select
    when diagnostic_blocked.receive
    when timeout(2.seconds)
      raise "log publication diagnostic did not reach blocking log callback"
    end

    result = select
    when accepted = reconnect_result.receive
      accepted
    when timeout(2.seconds)
      raise "reconnect did not finish while diagnostic log fanout was blocked"
    end
    result.should be_true
    state.snapshot.last_error.should eq("OBS reconnect requested")
  ensure
    if release = release_diagnostic
      select
      when release.send(nil)
      else
      end
    end
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_supervisor { !supervisor.alive? } if supervisor
  end

  it "rejects reconnect after stop before publishing reconnect state" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    state = Obsctl::Server::StateStore.new
    supervisor = Obsctl::Server::ObsSupervisor.new(obs.config, state)

    supervisor.start
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_supervisor { state.snapshot.connected }

    supervisor.stop
    snapshot_before_reconnect = state.snapshot
    telemetry_before_reconnect = state.telemetry

    supervisor.reconnect.should be_false

    supervisor.alive?.should be_false
    supervisor.stopped_reconnect_attempted?.should be_true
    state.snapshot.should eq(snapshot_before_reconnect)
    state.telemetry.should eq(telemetry_before_reconnect)
    state.snapshot.last_error.should_not eq("OBS reconnect requested")
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
