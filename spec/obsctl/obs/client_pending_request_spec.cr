require "../../spec_helper"
require "../../support/fake_obs_server"
require "../../../src/obsctl/obs/client"

class Obsctl::OBS::Client
  def pending_request_count_for_spec : Int32
    @pending_lock.synchronize { @pending.size }
  end
end

describe Obsctl::OBS::Client do
  it "does not let a late timeout response satisfy a later request" do
    server = Obsctl::SpecSupport::FakeObsServer.new(
      request_delays: {"GetVersion" => 400.milliseconds},
      request_timeout_ms: 150
    ).start
    client = Obsctl::OBS::Client.new(server.config)

    begin
      client.connect

      expect_raises(Obsctl::Domain::RequestTimeout) do
        client.version
      end
      client.pending_request_count_for_spec.should eq(0)

      client.current_scene.should eq("Main Camera")
      server.next_delayed_response.should eq("GetVersion")

      client.pending_request_count_for_spec.should eq(0)
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "correlates multiple concurrent requests by request id" do
    server = Obsctl::SpecSupport::FakeObsServer.new(
      request_delays: {"GetVersion" => 150.milliseconds},
      request_timeout_ms: 1_000
    ).start
    client = Obsctl::OBS::Client.new(server.config)
    version_result = Channel(String | Exception).new(1)
    scene_result = Channel(String | Exception).new(1)

    begin
      client.connect

      spawn do
        begin
          version_result.send(client.version["obsVersion"].as_s)
        rescue ex
          version_result.send(ex)
        end
      end
      server.next_request.should eq("GetVersion")

      spawn do
        begin
          scene_result.send(client.current_scene || "")
        rescue ex
          scene_result.send(ex)
        end
      end
      server.next_request.should eq("GetCurrentProgramScene")

      receive_result(scene_result, 500.milliseconds).should eq("Main Camera")
      receive_result(version_result, 1.second).should eq("31.0.0")
      client.pending_request_count_for_spec.should eq(0)
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "fails an in-flight request promptly when OBS disconnects" do
    server = Obsctl::SpecSupport::FakeObsServer.new(
      request_delays: {"GetVersion" => 2.seconds},
      request_timeout_ms: 2_000
    ).start
    client = Obsctl::OBS::Client.new(server.config)
    result = Channel(Exception?).new(1)

    begin
      client.connect
      spawn do
        begin
          client.version
          result.send(nil)
        rescue ex
          result.send(ex)
        end
      end

      server.next_request.should eq("GetVersion")
      started = Time.instant
      server.close_connections

      error = receive_result(result, 1.second)
      elapsed = Time.instant - started
      error.should be_a(Obsctl::Domain::ConnectionFailed)
      elapsed.should be < 1.second
      client.pending_request_count_for_spec.should eq(0)
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "clears pending requests when a malformed OBS frame is read" do
    server = Obsctl::SpecSupport::FakeObsServer.new(
      request_delays: {"GetVersion" => 2.seconds},
      request_timeout_ms: 2_000
    ).start
    client = Obsctl::OBS::Client.new(server.config)
    result = Channel(Exception?).new(1)

    begin
      client.connect
      spawn do
        begin
          client.version
          result.send(nil)
        rescue ex
          result.send(ex)
        end
      end

      server.next_request.should eq("GetVersion")
      server.emit_raw_frame("{not-json")

      error = receive_result(result, 1.second)
      error.should be_a(Obsctl::Domain::ConnectionFailed)
      error.not_nil!.message.to_s.should contain("malformed OBS frame")
      client.terminal_error.not_nil!.message.to_s.should contain("malformed OBS frame")
      client.pending_request_count_for_spec.should eq(0)
      client.connected?.should be_false
      server.next_close.should be_true
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "closes the websocket and clears pending requests when response parsing fails" do
    server = Obsctl::SpecSupport::FakeObsServer.new(
      request_delays: {"GetVersion" => 2.seconds},
      request_timeout_ms: 2_000
    ).start
    client = Obsctl::OBS::Client.new(server.config)
    result = Channel(Exception?).new(1)

    begin
      client.connect
      spawn do
        begin
          client.version
          result.send(nil)
        rescue ex
          result.send(ex)
        end
      end

      server.next_request.should eq("GetVersion")
      server.emit_raw_frame(%({"op":7,"d":{"requestType":"GetVersion","requestStatus":{"result":true,"code":100}}}))

      error = receive_result(result, 1.second)
      error.should be_a(Obsctl::Domain::ConnectionFailed)
      error.not_nil!.message.to_s.should contain("response parser error")
      client.terminal_error.not_nil!.message.to_s.should contain("response parser error")
      client.pending_request_count_for_spec.should eq(0)
      client.connected?.should be_false
      server.next_close.should be_true
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "leaves no pending channel registered after request timeout" do
    server = Obsctl::SpecSupport::FakeObsServer.new(
      request_delays: {"GetCurrentProgramScene" => 400.milliseconds},
      request_timeout_ms: 150
    ).start
    client = Obsctl::OBS::Client.new(server.config)

    begin
      client.connect

      expect_raises(Obsctl::Domain::RequestTimeout) do
        client.current_scene
      end

      client.pending_request_count_for_spec.should eq(0)
    ensure
      client.try(&.close)
      server.stop
    end
  end
end

private def receive_result(channel : Channel(T), wait : Time::Span) : T forall T
  select
  when result = channel.receive
    result
  when timeout(wait)
    raise "timed out waiting for OBS client request result"
  end
end
