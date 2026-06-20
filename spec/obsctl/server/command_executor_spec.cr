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
) : Obsctl::Server::CommandExecutor
  state = Obsctl::Server::StateStore.new
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

describe Obsctl::Server::CommandExecutor do
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
