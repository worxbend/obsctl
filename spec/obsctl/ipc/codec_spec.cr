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
      Obsctl::IPC::ErrorPayload.new("OBS_UNAVAILABLE", "OBS is unavailable")
    )

    decoded = codec.decode(codec.encode(response)).as(Obsctl::IPC::Response)

    decoded.ok.should be_false
    decoded.error.not_nil!.code.should eq("OBS_UNAVAILABLE")
    decoded.error.not_nil!.message.should eq("OBS is unavailable")
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
