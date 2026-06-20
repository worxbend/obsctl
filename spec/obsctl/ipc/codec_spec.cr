require "../../spec_helper"
require "../../../src/obsctl/ipc/protocol"

describe Obsctl::IPC::Codec do
  codec = Obsctl::IPC::Codec.new

  it "encodes and decodes command requests" do
    request = Obsctl::IPC::Request.new(
      "req-000001",
      Obsctl::IPC::Request::TYPE_COMMAND,
      Obsctl::IPC::CommandPayload.new("set_scene", "main")
    )

    decoded = codec.decode(codec.encode(request)).as(Obsctl::IPC::Request)

    decoded.id.should eq("req-000001")
    decoded.command?.should be_true
    decoded.command.not_nil!.name.should eq("set_scene")
    decoded.command.not_nil!.target.should eq("main")
  end

  it "encodes and decodes subscribe requests" do
    request = Obsctl::IPC::Request.new(
      "req-000002",
      Obsctl::IPC::Request::TYPE_SUBSCRIBE,
      nil,
      ["state", "events"]
    )

    decoded = codec.decode(codec.encode(request)).as(Obsctl::IPC::Request)

    decoded.subscribe?.should be_true
    decoded.topics.should eq(["state", "events"])
  end

  it "encodes and decodes success responses" do
    response = Obsctl::IPC::Response.new(
      "req-000003",
      true,
      JSON.parse(%({"message":"pong"}))
    )

    decoded = codec.decode(codec.encode(response)).as(Obsctl::IPC::Response)

    decoded.id.should eq("req-000003")
    decoded.ok.should be_true
    decoded.result.not_nil!["message"].as_s.should eq("pong")
  end

  it "encodes and decodes error responses" do
    response = Obsctl::IPC::Response.new(
      "req-000004",
      false,
      nil,
      Obsctl::IPC::ErrorPayload.new(Obsctl::IPC::ErrorCode::OBS_UNAVAILABLE, "OBS is unavailable")
    )

    decoded = codec.decode(codec.encode(response)).as(Obsctl::IPC::Response)

    decoded.ok.should be_false
    decoded.error.not_nil!.code.should eq("OBS_UNAVAILABLE")
    decoded.error.not_nil!.message.should eq("OBS is unavailable")
  end

  it "keeps public IPC error codes canonical" do
    Obsctl::IPC::ErrorCode::CODES.each do |code|
      payload = Obsctl::IPC::ErrorPayload.new(code, "safe message")
      payload.code.should eq(code)
    end
  end

  it "canonicalizes legacy vague IPC error codes at the boundary" do
    Obsctl::IPC::ErrorPayload.new("CONFIG_ERROR", "bad config").code.should eq(Obsctl::IPC::ErrorCode::CONFIG_INVALID)
    Obsctl::IPC::ErrorPayload.new("REQUEST_FAILED", "OBS failed").code.should eq(Obsctl::IPC::ErrorCode::OBS_REQUEST_FAILED)
    Obsctl::IPC::ErrorPayload.new("INVALID_REQUEST", "bad IPC").code.should eq(Obsctl::IPC::ErrorCode::IPC_PROTOCOL_ERROR)
    Obsctl::IPC::ErrorPayload.new("INTERNAL_ERROR", "boom").code.should eq(Obsctl::IPC::ErrorCode::SERVER_ERROR)
  end

  it "rejects non-canonical public IPC error codes" do
    expect_raises(Obsctl::Domain::IpcProtocolError, "non-canonical IPC error code") do
      Obsctl::IPC::ErrorPayload.new("BOGUS", "bad code")
    end
  end

  it "redacts obvious secrets from IPC error messages" do
    payload = Obsctl::IPC::ErrorPayload.new(
      Obsctl::IPC::ErrorCode::SERVER_ERROR,
      "failed with password=supersecret token: abc123"
    )

    payload.message.should_not contain("supersecret")
    payload.message.should_not contain("abc123")
    payload.message.should contain("[redacted]")
  end

  it "redacts quoted secret values from IPC error messages" do
    payload = Obsctl::IPC::ErrorPayload.new(
      Obsctl::IPC::ErrorCode::SERVER_ERROR,
      "OBS rejected password \"super secret\" and token='abc 123'"
    )

    payload.message.should_not contain("super secret")
    payload.message.should_not contain("abc 123")
    payload.message.should contain("password [redacted]")
    payload.message.should contain("token=[redacted]")
  end

  it "redacts YAML-like secret fields from IPC error messages" do
    payload = Obsctl::IPC::ErrorPayload.new(
      Obsctl::IPC::ErrorCode::CONFIG_INVALID,
      "invalid config: password: hunter2 secret: 'abc 123'"
    )

    payload.message.should_not contain("hunter2")
    payload.message.should_not contain("abc 123")
    payload.message.should contain("password: [redacted]")
    payload.message.should contain("secret: [redacted]")
  end

  it "redacts natural-language secret messages from IPC errors" do
    payload = Obsctl::IPC::ErrorPayload.new(
      Obsctl::IPC::ErrorCode::OBS_REQUEST_FAILED,
      "OBS reported authentication string is generated-token and password is hunter2"
    )

    payload.message.should_not contain("generated-token")
    payload.message.should_not contain("hunter2")
    payload.message.should contain("authentication string is [redacted]")
    payload.message.should contain("password is [redacted]")
  end

  it "encodes and decodes events" do
    event = Obsctl::IPC::Event.new("state", JSON.parse(%({"connected":true})))

    decoded = codec.decode(codec.encode(event)).as(Obsctl::IPC::Event)

    decoded.topic.should eq("state")
    decoded.data.not_nil!["connected"].as_bool.should be_true
  end

  it "rejects unknown message types" do
    expect_raises(Obsctl::Domain::IpcProtocolError, "unknown IPC message type") do
      codec.decode(%({"type":"bogus"}))
    end
  end

  it "rejects malformed JSON" do
    expect_raises(Obsctl::Domain::IpcProtocolError, "invalid IPC JSON") do
      codec.decode("{")
    end
  end
end
