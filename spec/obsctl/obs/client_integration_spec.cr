require "../../spec_helper"
require "../../support/fake_obs_server"
require "../../../src/obsctl/obs/client"
require "../../../src/obsctl/obs/protocol/event_subscription"

describe Obsctl::OBS::Client do
  it "connects to fake obs-websocket and builds a snapshot" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    client = Obsctl::OBS::Client.new(server.config)

    begin
      client.connect
      snapshot = client.snapshot

      snapshot.connected.should be_true
      snapshot.obs_studio_version.should eq("31.0.0")
      snapshot.obs_websocket_version.should eq("5.4.0")
      snapshot.current_scene.should eq("Main Camera")

      snapshot.scenes.map(&.name).should eq(["Main Camera", "Screen Share", "BRB"])
      snapshot.scenes[0].alias.should eq("main")
      snapshot.scenes[0].shortcut.should eq("1")
      snapshot.scenes[0].active.should be_true
      snapshot.scenes[1].active.should be_false

      snapshot.audio_inputs.map(&.name).should eq(["Mic/Aux", "Desktop Audio"])
      snapshot.audio_inputs[0].alias.should eq("mic")
      snapshot.audio_inputs[0].muted.should be_false
      snapshot.audio_inputs[0].volume_mul.should eq(0.7)
      snapshot.audio_inputs[0].volume_percent.should eq(70)
      snapshot.audio_inputs[1].muted.should be_true
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "executes scene and audio command requests against fake obs-websocket" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    client = Obsctl::OBS::Client.new(server.config)

    begin
      client.connect

      client.set_scene("Screen Share")
      server.current_scene.should eq("Screen Share")
      client.current_scene.should eq("Screen Share")

      client.mute("Mic/Aux", true)
      server.input("Mic/Aux").not_nil!.muted.should be_true
      client.input_muted("Mic/Aux").should be_true

      client.toggle_mute("Mic/Aux")
      server.input("Mic/Aux").not_nil!.muted.should be_false

      client.set_volume("Mic/Aux", 25)
      server.input("Mic/Aux").not_nil!.volume_mul.should eq(0.25)
      client.input_volume("Mic/Aux")[:percent].should eq(25)
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "sends explicit event subscriptions when configured" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    client = Obsctl::OBS::Client.new(
      server.config,
      event_subscriptions: Obsctl::OBS::Protocol::EventSubscription::SERVER_DEFAULT
    )

    begin
      client.connect
      identify = wait_for_identify_data(server)

      identify["eventSubscriptions"].as_i.should eq(Obsctl::OBS::Protocol::EventSubscription::SERVER_DEFAULT)
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "fails an in-flight request when the websocket closes" do
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
      client.close

      error = result.receive
      elapsed = Time.instant - started
      error.should be_a(Obsctl::Domain::ConnectionFailed)
      elapsed.should be < 1.second
    ensure
      client.try(&.close)
      server.stop
    end
  end
end

private def wait_for_identify_data(server : Obsctl::SpecSupport::FakeObsServer) : JSON::Any
  20.times do
    if data = server.identify_data
      return data
    end
    sleep 50.milliseconds
  end

  raise "fake OBS server did not receive Identify data"
end
