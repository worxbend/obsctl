require "../../spec_helper"
require "../../../src/obsctl/server/best_effort_log_broadcast"
require "../../../src/obsctl/server/command_executor"
require "../../support/fake_obs_server"

private class FailingSupervisor < Obsctl::Server::ObsSupervisor
  def initialize(@failure : Exception)
    super(Obsctl::Config::Config.default, Obsctl::Server::StateStore.new)
  end

  def with_client(&block : Obsctl::OBS::Client -> T) : T forall T
    raise @failure
  end
end

private class ReconnectSupervisor < Obsctl::Server::ObsSupervisor
  getter reconnect_calls

  def initialize(@test_state : Obsctl::Server::StateStore, @test_alive : Bool)
    super(Obsctl::Config::Config.default, @test_state)
    @reconnect_calls = 0
  end

  def alive? : Bool
    @test_alive
  end

  def reconnect : Bool
    @reconnect_calls += 1
    return false unless @test_alive

    @test_state.mark_disconnected("OBS reconnect requested", reconnecting: true, connection_failed: false)
    true
  end
end

private def command_request(command : Obsctl::IPC::CommandPayload?) : Obsctl::IPC::Request
  Obsctl::IPC::Request.new("req-error", Obsctl::IPC::Request::TYPE_COMMAND, command)
end

private def default_executor(
  config : Obsctl::Config::Config = Obsctl::Config::Config.default,
  config_path : String = "/tmp/obsctl-command-executor-spec.yml",
  supervisor : Obsctl::Server::ObsSupervisor? = nil,
  state : Obsctl::Server::StateStore = Obsctl::Server::StateStore.new,
  dropped_reconnect_diagnostic_logs : Proc(UInt64)? = nil,
) : Obsctl::Server::CommandExecutor
  runtime_supervisor = supervisor || Obsctl::Server::ObsSupervisor.new(config, state)
  Obsctl::Server::CommandExecutor.new(
    config,
    config_path,
    state,
    runtime_supervisor,
    "/tmp/obsctl.sock",
    dropped_reconnect_diagnostic_logs: dropped_reconnect_diagnostic_logs
  )
end

private def expect_error(response : Obsctl::IPC::Response, code : String) : Obsctl::IPC::ErrorPayload
  response.ok.should be_false
  error = response.error.not_nil!
  error.code.should eq(code)
  Obsctl::IPC::ErrorCode::CODES.should contain(error.code)
  error.message.should_not contain("supersecret")
  error.message.should_not contain("abc123")
  error
end

private def parse_rfc3339(value : JSON::Any) : Time
  Time.parse_rfc3339(value.as_s)
end

private def wait_for_command_executor_supervisor(timeout : Time::Span = 3.seconds, &block : -> Bool) : Nil
  deadline = Time.instant + timeout

  until block.call
    raise "timed out waiting for supervisor condition" if Time.instant >= deadline
    Fiber.yield
  end
end

private def next_command_executor_websocket_connection_id(
  obs : Obsctl::SpecSupport::FakeObsServer,
  timeout : Time::Span = 2.seconds,
) : Int64
  obs.next_accepted_websocket_connection_id(timeout) || raise "fake OBS did not accept WebSocket connection"
end

private def command_executor_diagnostic_log_broadcast_for(log_broadcast : Proc(JSON::Any, Nil)) : Proc(JSON::Any, Bool)
  helper = Obsctl::Server::BestEffortLogBroadcast.new(log_broadcast)
  ->(payload : JSON::Any) { helper.broadcast(payload) }
end

describe Obsctl::Server::CommandExecutor do
  it "returns distinct combined, OBS-only, and daemon-only status payloads" do
    state = Obsctl::Server::StateStore.new
    state.update(Obsctl::OBS::State::ObsSnapshot.new(
      connected: true,
      obs_studio_version: "30.1.0",
      obs_websocket_version: "5.3.0",
      current_scene: "Main Camera",
      scenes: [
        Obsctl::OBS::State::SceneState.new("Main Camera", active: true),
      ],
      audio_inputs: [
        Obsctl::OBS::State::AudioState.new("Mic/Aux", muted: false, volume_percent: 72),
      ]
    ))
    executor = default_executor(state: state, dropped_reconnect_diagnostic_logs: -> { 7_u64 })

    combined = executor.execute(command_request(Obsctl::IPC::CommandPayload.new("status")))
    obs_only = executor.execute(command_request(Obsctl::IPC::CommandPayload.new("get_obs_status")))
    daemon_only = executor.execute(command_request(Obsctl::IPC::CommandPayload.new("get_server_status")))

    combined.ok.should be_true
    combined_result = combined.result.not_nil!
    combined_result["server"]["pid"].as_i.should eq(Process.pid)
    combined_result["server"]["obs_connected"].as_bool.should be_true
    combined_result["server"]["dropped_reconnect_diagnostic_logs"].as_i64.should eq(7)
    parse_rfc3339(combined_result["server"]["last_connected_at"]).should be_a(Time)
    combined_result["server"]["last_disconnected_at"].raw.should be_nil
    combined_result["server"]["last_reconnect_attempt_at"].raw.should be_nil
    combined_result["server"]["last_connection_failed_at"].raw.should be_nil
    combined_result["obs"]["connected"].as_bool.should be_true
    combined_result["obs"]["current_scene"].as_s.should eq("Main Camera")

    obs_only.ok.should be_true
    obs_only_result = obs_only.result.not_nil!
    obs_only_result["connected"].as_bool.should be_true
    obs_only_result["current_scene"].as_s.should eq("Main Camera")
    obs_only_result["server"]?.should be_nil
    obs_only_result["obs"]?.should be_nil

    daemon_only.ok.should be_true
    daemon_result = daemon_only.result.not_nil!
    daemon_result["pid"].as_i.should eq(Process.pid)
    daemon_result["obs_connected"].as_bool.should be_true
    daemon_result["dropped_reconnect_diagnostic_logs"].as_i64.should eq(7)
    parse_rfc3339(daemon_result["last_connected_at"]).should be_a(Time)
    daemon_result["last_disconnected_at"].raw.should be_nil
    daemon_result["last_reconnect_attempt_at"].raw.should be_nil
    daemon_result["last_connection_failed_at"].raw.should be_nil
    daemon_result["connected"]?.should be_nil
  end

  it "keeps absent daemon reconnect timestamps as JSON nulls" do
    response = default_executor.execute(command_request(Obsctl::IPC::CommandPayload.new("get_server_status")))

    response.ok.should be_true
    result = response.result.not_nil!
    result["obs_connected"].as_bool.should be_false
    result["reconnecting"].as_bool.should be_false
    result["dropped_reconnect_diagnostic_logs"].as_i64.should eq(0)
    result["last_connected_at"].raw.should be_nil
    result["last_disconnected_at"].raw.should be_nil
    result["last_reconnect_attempt_at"].raw.should be_nil
    result["last_connection_failed_at"].raw.should be_nil
  end

  it "returns IPC_PROTOCOL_ERROR for malformed command requests" do
    response = default_executor.execute(command_request(nil))

    expect_error(response, Obsctl::IPC::ErrorCode::IPC_PROTOCOL_ERROR)
  end

  it "returns COMMAND_PARSE_ERROR for unsupported IPC commands" do
    response = default_executor.execute(command_request(Obsctl::IPC::CommandPayload.new("bogus")))

    expect_error(response, Obsctl::IPC::ErrorCode::COMMAND_PARSE_ERROR)
  end

  it "returns CONFIG_INVALID for server-side config load failures" do
    path = File.join(Dir.tempdir, "obsctl-command-executor-missing-#{Random.rand(1_000_000)}.yml")

    response = default_executor(config_path: path).execute(
      command_request(Obsctl::IPC::CommandPayload.new("validate_config"))
    )

    expect_error(response, Obsctl::IPC::ErrorCode::CONFIG_INVALID)
  end

  it "returns SHUTDOWN_DISABLED when remote shutdown is not enabled" do
    response = default_executor.execute(command_request(Obsctl::IPC::CommandPayload.new("shutdown_server")))

    expect_error(response, Obsctl::IPC::ErrorCode::SHUTDOWN_DISABLED)
  end

  it "returns SCENE_NOT_FOUND for unknown scene targets" do
    config = Obsctl::Config::Config.new(
      scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera", "main"),
      ]
    )

    response = default_executor(config).execute(
      command_request(Obsctl::IPC::CommandPayload.new("set_scene", "missing"))
    )

    expect_error(response, Obsctl::IPC::ErrorCode::SCENE_NOT_FOUND)
  end

  it "returns AUDIO_INPUT_NOT_FOUND for unknown audio targets" do
    config = Obsctl::Config::Config.new(
      audio: Obsctl::Config::AudioConfig.new([
        Obsctl::Config::AudioInputConfig.new("Mic/Aux", "mic"),
      ])
    )

    response = default_executor(config).execute(
      command_request(Obsctl::IPC::CommandPayload.new("mute", "missing"))
    )

    expect_error(response, Obsctl::IPC::ErrorCode::AUDIO_INPUT_NOT_FOUND)
  end

  it "returns ALIAS_AMBIGUOUS for ambiguous scene aliases" do
    config = Obsctl::Config::Config.new(
      scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera", "cam"),
        Obsctl::Config::SceneConfig.new("Side Camera", "CAM"),
      ]
    )

    response = default_executor(config).execute(
      command_request(Obsctl::IPC::CommandPayload.new("set_scene", "Cam"))
    )

    expect_error(response, Obsctl::IPC::ErrorCode::ALIAS_AMBIGUOUS)
  end

  it "returns OBS_UNAVAILABLE while the server has no active OBS client" do
    config = Obsctl::Config::Config.new(
      scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera", "main"),
      ]
    )

    response = default_executor(config).execute(
      command_request(Obsctl::IPC::CommandPayload.new("set_scene", "main"))
    )

    expect_error(response, Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE)
  end

  it "accepts reconnect only when the supervisor is alive" do
    state = Obsctl::Server::StateStore.new
    supervisor = ReconnectSupervisor.new(state, true)

    response = default_executor(supervisor: supervisor, state: state).execute(
      command_request(Obsctl::IPC::CommandPayload.new("reconnect_obs"))
    )

    response.ok.should be_true
    response.result.not_nil!["message"].as_s.should eq("OBS reconnect requested")
    supervisor.reconnect_calls.should eq(1)
    state.snapshot.last_error.should eq("OBS reconnect requested")
  end

  it "returns reconnect success when accepted state publication raises and records a sanitized diagnostic" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    logs = [] of JSON::Any
    logs_lock = Mutex.new
    state = Obsctl::Server::StateStore.new(->(payload : JSON::Any) {
      if payload["last_error"]?.try(&.as_s?) == "OBS reconnect requested"
        raise "state publication failed password=supersecret token: abc123"
      end
    })
    log_broadcast = ->(payload : JSON::Any) {
      logs_lock.synchronize { logs << payload }
    }
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      log_broadcast,
      nil,
      command_executor_diagnostic_log_broadcast_for(log_broadcast)
    )

    supervisor.start
    connection_id = next_command_executor_websocket_connection_id(obs)
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_command_executor_supervisor { state.snapshot.connected }

    response = default_executor(obs.config, supervisor: supervisor, state: state).execute(
      command_request(Obsctl::IPC::CommandPayload.new("reconnect_obs"))
    )

    response.ok.should be_true
    response.error.should be_nil
    response.result.not_nil!["message"].as_s.should eq("OBS reconnect requested")
    obs.assert_websocket_connection_closed(connection_id, 2.seconds)
    state.snapshot.last_error.should eq("OBS reconnect requested")
    wait_for_command_executor_supervisor do
      logs_lock.synchronize do
        logs.any? { |entry| entry["code"]?.try(&.as_s?) == "obs_reconnect_state_publication_failed" }
      end
    end

    messages = logs_lock.synchronize { logs.map { |entry| entry["message"].as_s }.join("\n") }
    messages.should contain("OBS reconnect state publication failed")
    messages.should_not contain("supersecret")
    messages.should_not contain("abc123")
    messages.should contain("[redacted]")
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_command_executor_supervisor { !supervisor.alive? } if supervisor
  end

  it "returns reconnect success when accepted log publication raises and records a sanitized diagnostic" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    logs = [] of JSON::Any
    logs_lock = Mutex.new
    state = Obsctl::Server::StateStore.new
    log_broadcast = ->(payload : JSON::Any) {
      if payload["code"]?.try(&.as_s?) == "obs_reconnect_requested"
        raise "log publication failed password=supersecret token: abc123"
      end

      logs_lock.synchronize { logs << payload }
    }
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      log_broadcast,
      nil,
      command_executor_diagnostic_log_broadcast_for(log_broadcast)
    )

    supervisor.start
    connection_id = next_command_executor_websocket_connection_id(obs)
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_command_executor_supervisor { state.snapshot.connected }

    response = default_executor(obs.config, supervisor: supervisor, state: state).execute(
      command_request(Obsctl::IPC::CommandPayload.new("reconnect_obs"))
    )

    response.ok.should be_true
    response.error.should be_nil
    response.result.not_nil!["message"].as_s.should eq("OBS reconnect requested")
    obs.assert_websocket_connection_closed(connection_id, 2.seconds)
    state.snapshot.last_error.should eq("OBS reconnect requested")
    wait_for_command_executor_supervisor do
      logs_lock.synchronize do
        logs.any? { |entry| entry["code"]?.try(&.as_s?) == "obs_reconnect_log_publication_failed" }
      end
    end

    diagnostics = logs_lock.synchronize do
      logs.select { |entry| entry["code"]?.try(&.as_s?) == "obs_reconnect_log_publication_failed" }
    end
    diagnostics.size.should eq(1)
    diagnostic_message = diagnostics.first["message"].as_s
    diagnostic_message.should contain("OBS reconnect log publication failed")
    diagnostic_message.should_not contain("supersecret")
    diagnostic_message.should_not contain("abc123")
    diagnostic_message.should contain("[redacted]")
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_command_executor_supervisor { !supervisor.alive? } if supervisor
  end

  it "writes one sanitized runtime diagnostic when secondary diagnostic delivery succeeds" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    log_path = File.join(Dir.tempdir, "obsctl-command-reconnect-secondary-success-#{Random.rand(1_000_000)}.log")
    logs = [] of JSON::Any
    logs_lock = Mutex.new
    state = Obsctl::Server::StateStore.new(->(payload : JSON::Any) {
      if payload["last_error"]?.try(&.as_s?) == "OBS reconnect requested"
        raise "state publication failed password=supersecret token: abc123"
      end
    })
    logger = Obsctl::Runtime::Logger.new(Obsctl::Runtime::LogLevel::Warn, log_path)
    server_style_log_broadcast = ->(payload : JSON::Any) {
      logs_lock.synchronize { logs << payload }
      level = payload["level"]?.try(&.as_s?) || "info"
      code = payload["code"]?.try(&.as_s?) || "server"
      message = payload["message"]?.try(&.as_s?) || ""
      logger.write(level, "#{code} #{message}")
    }
    diagnostic_log_broadcast = Obsctl::Server::BestEffortLogBroadcast.new(->(payload : JSON::Any) {
      logs_lock.synchronize { logs << payload }
    })
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      server_style_log_broadcast,
      logger,
      ->(payload : JSON::Any) { diagnostic_log_broadcast.broadcast(payload) }
    )

    supervisor.start
    connection_id = next_command_executor_websocket_connection_id(obs)
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_command_executor_supervisor { state.snapshot.connected }

    response = default_executor(obs.config, supervisor: supervisor, state: state).execute(
      command_request(Obsctl::IPC::CommandPayload.new("reconnect_obs"))
    )

    response.ok.should be_true
    response.error.should be_nil
    response.result.not_nil!["message"].as_s.should eq("OBS reconnect requested")
    obs.assert_websocket_connection_closed(connection_id, 2.seconds)
    wait_for_command_executor_supervisor do
      logs_lock.synchronize do
        logs.any? { |entry| entry["code"]?.try(&.as_s?) == "obs_reconnect_state_publication_failed" }
      end
    end
    wait_for_command_executor_supervisor do
      File.exists?(log_path) && File.read(log_path).includes?("obs_reconnect_state_publication_failed")
    end

    diagnostics = logs_lock.synchronize do
      logs.select { |entry| entry["code"]?.try(&.as_s?) == "obs_reconnect_state_publication_failed" }
    end
    diagnostics.size.should eq(1)
    diagnostics.first["message"].as_s.should contain("[redacted]")

    log = File.read(log_path)
    log.scan(/obs_reconnect_state_publication_failed/).size.should eq(1)
    log.should contain("OBS reconnect state publication failed")
    log.should contain("[redacted]")
    log.should_not contain("supersecret")
    log.should_not contain("abc123")
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_command_executor_supervisor { !supervisor.alive? } if supervisor
    File.delete(log_path) if log_path && File.exists?(log_path)
  end

  it "returns reconnect success and writes one sanitized runtime diagnostic when diagnostic log publication raises" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    log_path = File.join(Dir.tempdir, "obsctl-command-reconnect-diagnostic-#{Random.rand(1_000_000)}.log")
    diagnostic_attempted = Channel(Nil).new(1)
    state = Obsctl::Server::StateStore.new
    logger = Obsctl::Runtime::Logger.new(Obsctl::Runtime::LogLevel::Warn, log_path)
    log_broadcast = ->(payload : JSON::Any) {
      case payload["code"]?.try(&.as_s?)
      when "obs_reconnect_requested"
        raise "log publication failed password=supersecret token: abc123 authentication string is generated-auth"
      when "obs_reconnect_log_publication_failed"
        diagnostic_attempted.send(nil)
        raise "diagnostic log publication failed token: fallback-token secret=sesame"
      end
    }
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      log_broadcast,
      logger,
      command_executor_diagnostic_log_broadcast_for(log_broadcast)
    )

    supervisor.start
    connection_id = next_command_executor_websocket_connection_id(obs)
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_command_executor_supervisor { state.snapshot.connected }

    response = default_executor(obs.config, supervisor: supervisor, state: state).execute(
      command_request(Obsctl::IPC::CommandPayload.new("reconnect_obs"))
    )

    response.ok.should be_true
    response.error.should be_nil
    response.result.not_nil!["message"].as_s.should eq("OBS reconnect requested")
    obs.assert_websocket_connection_closed(connection_id, 2.seconds)
    state.snapshot.last_error.should eq("OBS reconnect requested")

    select
    when diagnostic_attempted.receive
    when timeout(2.seconds)
      raise "diagnostic log publication was not attempted"
    end
    wait_for_command_executor_supervisor do
      File.exists?(log_path) && File.read(log_path).includes?("OBS reconnect log publication failed")
    end

    log = File.read(log_path)
    log.should contain("level=warn")
    log.should contain("obs_reconnect_log_publication_failed")
    log.should contain("OBS reconnect log publication failed")
    log.should contain("[redacted]")
    log.scan(/obs_reconnect_log_publication_failed/).size.should eq(1)
    log.should_not contain("supersecret")
    log.should_not contain("abc123")
    log.should_not contain("generated-auth")
    log.should_not contain("fallback-token")
    log.should_not contain("sesame")
    log.should_not contain("diagnostic log publication failed")
  ensure
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_command_executor_supervisor { !supervisor.alive? } if supervisor
    File.delete(log_path) if log_path && File.exists?(log_path)
  end

  it "writes one sanitized runtime diagnostic while secondary diagnostic delivery is blocked" do
    obs = Obsctl::SpecSupport::FakeObsServer.new.start
    log_path = File.join(Dir.tempdir, "obsctl-command-reconnect-secondary-blocked-#{Random.rand(1_000_000)}.log")
    diagnostic_blocked = Channel(Nil).new(1)
    release_diagnostic = Channel(Nil).new(1)
    diagnostic_reached = false
    state = Obsctl::Server::StateStore.new(->(payload : JSON::Any) {
      if payload["last_error"]?.try(&.as_s?) == "OBS reconnect requested"
        raise "state publication failed secret=sesame token: abc123"
      end
    })
    logger = Obsctl::Runtime::Logger.new(Obsctl::Runtime::LogLevel::Warn, log_path)
    log_broadcast = ->(_payload : JSON::Any) { }
    diagnostic_log_broadcast = Obsctl::Server::BestEffortLogBroadcast.new(->(payload : JSON::Any) {
      if payload["code"]?.try(&.as_s?) == "obs_reconnect_state_publication_failed"
        diagnostic_blocked.send(nil)
        release_diagnostic.receive
      end
    })
    supervisor = Obsctl::Server::ObsSupervisor.new(
      obs.config,
      state,
      nil,
      log_broadcast,
      logger,
      ->(payload : JSON::Any) { diagnostic_log_broadcast.broadcast(payload) }
    )

    supervisor.start
    connection_id = next_command_executor_websocket_connection_id(obs)
    obs.next_identify(2.seconds).should_not be_nil
    wait_for_command_executor_supervisor { state.snapshot.connected }

    response = default_executor(obs.config, supervisor: supervisor, state: state).execute(
      command_request(Obsctl::IPC::CommandPayload.new("reconnect_obs"))
    )

    response.ok.should be_true
    response.error.should be_nil
    response.result.not_nil!["message"].as_s.should eq("OBS reconnect requested")
    obs.assert_websocket_connection_closed(connection_id, 2.seconds)

    select
    when diagnostic_blocked.receive
      diagnostic_reached = true
    when timeout(2.seconds)
      raise "secondary diagnostic delivery did not block"
    end

    log = File.read(log_path)
    log.scan(/obs_reconnect_state_publication_failed/).size.should eq(1)
    log.should contain("OBS reconnect state publication failed")
    log.should contain("[redacted]")
    log.should_not contain("sesame")
    log.should_not contain("abc123")
  ensure
    if diagnostic_reached
      release_diagnostic.try(&.send(nil))
    end
    supervisor.try(&.stop)
    obs.try(&.stop)
    wait_for_command_executor_supervisor { !supervisor.alive? } if supervisor
    File.delete(log_path) if log_path && File.exists?(log_path)
  end

  it "returns a public error for reconnect when the supervisor has exited" do
    state = Obsctl::Server::StateStore.new
    state.mark_disconnected("startup connection failed")
    supervisor = ReconnectSupervisor.new(state, false)

    response = default_executor(supervisor: supervisor, state: state).execute(
      command_request(Obsctl::IPC::CommandPayload.new("reconnect_obs"))
    )

    error = expect_error(response, Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE)
    error.message.should eq("OBS supervisor is not running; restart the server or enable reconnect.")
    supervisor.reconnect_calls.should eq(0)
    state.snapshot.last_error.should eq("startup connection failed")
  end

  it "returns REQUEST_TIMEOUT for OBS request timeouts" do
    config = Obsctl::Config::Config.new(
      scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera", "main"),
      ]
    )
    supervisor = FailingSupervisor.new(Obsctl::Domain::RequestTimeout.new("SetCurrentProgramScene"))

    response = default_executor(config, supervisor: supervisor).execute(
      command_request(Obsctl::IPC::CommandPayload.new("set_scene", "main"))
    )

    expect_error(response, Obsctl::IPC::ErrorCode::REQUEST_TIMEOUT)
  end

  it "returns OBS_REQUEST_FAILED and redacts secrets from OBS failure messages" do
    config = Obsctl::Config::Config.new(
      scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera", "main"),
      ]
    )
    failure = Obsctl::Domain::ObsRequestFailed.new("SetCurrentProgramScene", "password=supersecret token: abc123")
    supervisor = FailingSupervisor.new(failure)

    response = default_executor(config, supervisor: supervisor).execute(
      command_request(Obsctl::IPC::CommandPayload.new("set_scene", "main"))
    )

    error = expect_error(response, Obsctl::IPC::ErrorCode::OBS_REQUEST_FAILED)
    error.message.should contain("[redacted]")
  end

  it "returns SERVER_ERROR with a generic public message for unexpected failures" do
    config = Obsctl::Config::Config.new(
      scenes: [
        Obsctl::Config::SceneConfig.new("Main Camera", "main"),
      ]
    )
    supervisor = FailingSupervisor.new(Exception.new("password=supersecret token: abc123"))

    response = default_executor(config, supervisor: supervisor).execute(
      command_request(Obsctl::IPC::CommandPayload.new("set_scene", "main"))
    )

    error = expect_error(response, Obsctl::IPC::ErrorCode::SERVER_ERROR)
    error.message.should eq("internal server error")
  end
end
