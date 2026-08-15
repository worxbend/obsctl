require "../../spec_helper"
require "../../support/fake_obs_server"
require "../../../src/obsctl/obs/client"
require "../../../src/obsctl/obs/auth"
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
      snapshot.output.streaming.should be_false
      snapshot.output.recording.should be_false
      snapshot.profiles.should eq(["Default", "Streaming"])
      snapshot.current_profile.should eq("Default")
      snapshot.scene_collections.should eq(["Podcast", "Gaming"])
      snapshot.current_scene_collection.should eq("Podcast")
      snapshot.stats.try(&.cpu_usage_percent).should eq(12.5)
      snapshot.stats.try(&.active_fps).should eq(59.94)
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "builds a snapshot around inputs that have no audio to report" do
    server = Obsctl::SpecSupport::FakeObsServer.new(
      inputs: [
        Obsctl::SpecSupport::FakeObsServer::AudioInput.new("Mic/Aux", "input", false, 0.7, -3.0),
        # An image or colour source: listed by GetInputList, but OBS refuses to
        # report its mute or volume.
        Obsctl::SpecSupport::FakeObsServer::AudioInput.new("Overlay", "image_source", audio: false),
        Obsctl::SpecSupport::FakeObsServer::AudioInput.new("Desktop Audio", "output", true, 0.4, -8.0),
      ]
    ).start
    client = Obsctl::OBS::Client.new(server.config)

    begin
      client.connect

      # The whole snapshot used to fail here, which the supervisor read as a
      # lost connection and retried forever.
      snapshot = client.snapshot
      snapshot.connected.should be_true
      snapshot.audio_inputs.map(&.name).should eq(["Mic/Aux", "Desktop Audio"])
      snapshot.audio_inputs[0].volume_percent.should eq(70)

      client.audio_snapshot.map(&.name).should eq(["Mic/Aux", "Desktop Audio"])
    ensure
      client.close
      server.stop
    end
  end

  it "queries and switches profiles and scene collections" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    client = Obsctl::OBS::Client.new(server.config)
    begin
      client.connect
      client.profiles.should eq({current: "Default", names: ["Default", "Streaming"]})
      client.scene_collections.should eq({current: "Podcast", names: ["Podcast", "Gaming"]})
      client.set_profile("Streaming")
      client.set_scene_collection("Gaming")
      server.current_profile.should eq("Streaming")
      server.current_scene_collection.should eq("Gaming")
    ensure
      client.try(&.close)
      server.stop
    end
  end

  it "queries and toggles stream and record outputs" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    client = Obsctl::OBS::Client.new(server.config)
    begin
      client.connect
      client.output_state.should eq(Obsctl::OBS::State::OutputState.new(false, false))
      client.toggle_stream.should be_true
      client.toggle_record.should be_true
      server.streaming?.should be_true
      server.recording?.should be_true
      client.output_state.should eq(Obsctl::OBS::State::OutputState.new(true, true))
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

  it "answers an OBS authentication challenge with an empty password when none is configured" do
    env_name = "OBSCTL_SPEC_MISSING_PASSWORD"
    previous = ENV.delete(env_name)
    server = Obsctl::SpecSupport::FakeObsServer.new(authentication: true).start
    config = server.config
    config.connection = Obsctl::Config::ConnectionConfig.new(
      host: server.host,
      port: server.port,
      password_env: env_name,
      request_timeout_ms: 500
    )
    client = Obsctl::OBS::Client.new(config)

    begin
      client.connect
      identify = wait_for_identify_data(server)
      identify["authentication"].as_s.should eq(
        Obsctl::OBS::Auth.authentication("", "test-salt", "test-challenge")
      )
      client.connected?.should be_true
    ensure
      client.try(&.close)
      server.stop
      ENV["OBSCTL_SPEC_MISSING_PASSWORD"] = previous
    end
  end

  it "reports an open socket after Identify is rejected so the caller still closes it" do
    # A rejected Identify leaves the socket open and its reader fiber running.
    # Before this was tracked separately from `connected?`, the supervisor's
    # cleanup skipped `close` here and leaked one fd per reconnect attempt.
    server = Obsctl::SpecSupport::FakeObsServer.new(reject_identify: true).start
    client = Obsctl::OBS::Client.new(server.config)

    begin
      expect_raises(Obsctl::Domain::ObsctlError) { client.connect }

      client.connected?.should be_false
      client.socket_open?.should be_true
    ensure
      client.close
      server.stop
    end
  end

  it "delivers events in the order OBS sent them" do
    # Events used to be handed to the channel by one spawned fiber each, which
    # left the scheduler free to run them in any order — so an older volume for
    # an input could overwrite a newer one in daemon state.
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    client = Obsctl::OBS::Client.new(server.config)

    begin
      client.connect
      expected = (0...25).map { |index| "Scene #{index}" }
      expected.each { |name| server.emit_current_scene_changed(name) }

      received = expected.map do
        event = nil.as(Obsctl::OBS::Protocol::Event?)
        select
        when incoming = client.events.receive
          event = incoming
        when timeout(2.seconds)
        end
        event.not_nil!.event_data.not_nil!["sceneName"].as_s
      end

      received.should eq(expected)
    ensure
      client.close
      server.stop
    end
  end

  it "closes without raising when the socket was never opened" do
    # `@ws` is `uninitialized` until `connect` assigns it, so an unconditional
    # `close` from an error path must not dereference it.
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    client = Obsctl::OBS::Client.new(server.config)

    begin
      client.socket_open?.should be_false
      client.close
    ensure
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
        client.version
        result.send(nil)
      rescue ex
        result.send(ex)
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
