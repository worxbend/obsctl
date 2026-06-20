require "../../spec_helper"
require "../../../src/obsctl/server/command_executor"

private class FailingSupervisor < Obsctl::Server::ObsSupervisor
  def initialize(@failure : Exception)
    super(Obsctl::Config::Config.default, Obsctl::Server::StateStore.new)
  end

  def with_client(&block : Obsctl::OBS::Client -> T) : T forall T
    raise @failure
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
) : Obsctl::Server::CommandExecutor
  runtime_supervisor = supervisor || Obsctl::Server::ObsSupervisor.new(config, state)
  Obsctl::Server::CommandExecutor.new(config, config_path, state, runtime_supervisor, "/tmp/obsctl.sock")
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
    executor = default_executor(state: state)

    combined = executor.execute(command_request(Obsctl::IPC::CommandPayload.new("status")))
    obs_only = executor.execute(command_request(Obsctl::IPC::CommandPayload.new("get_obs_status")))
    daemon_only = executor.execute(command_request(Obsctl::IPC::CommandPayload.new("get_server_status")))

    combined.ok.should be_true
    combined_result = combined.result.not_nil!
    combined_result["server"]["pid"].as_i.should eq(Process.pid)
    combined_result["server"]["obs_connected"].as_bool.should be_true
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
