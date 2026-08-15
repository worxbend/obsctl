require "../../spec_helper"
require "../../../src/obsctl/ipc/protocol"
require "../../../src/obsctl/tui/session"

describe Obsctl::TUI::EventSession do
  it "subscribes to state, events, and logs then yields pushed events" do
    path = File.join(Dir.tempdir, "obsctl-tui-session-#{Random.rand(1_000_000)}.sock")
    server = Obsctl::IPC::UnixServer.new(path)
    ready = Channel(Nil).new
    done = Channel(Nil).new
    topics = Channel(Array(String)).new(1)
    spawn do
      server.bind
      ready.send(nil)
      client = server.accept
      request = client.read_message.as(Obsctl::IPC::Request)
      topics.send(request.topics)
      client.write_message(Obsctl::IPC::Response.new(request.id, true, JSON.parse(%({"message":"subscribed"}))))
      client.write_message(Obsctl::IPC::Event.new("state", JSON.parse(%({"connected":false}))))
      client.close
      done.send(nil)
    ensure
      server.close
    end

    ready.receive
    session = Obsctl::TUI::EventSession.connect(path)
    topics.receive.should eq(["state", "events", "logs"])
    event = session.next_event.not_nil!
    event.topic.should eq("state")
    event.data.not_nil!["connected"].as_bool.should be_false
    session.next_event.should be_nil
    done.receive
  ensure
    session.try(&.close)
    server.try(&.close)
  end
end

describe Obsctl::TUI::CommandClient do
  it "uses short-lived correlated command requests" do
    path = File.join(Dir.tempdir, "obsctl-tui-command-#{Random.rand(1_000_000)}.sock")
    server = Obsctl::IPC::UnixServer.new(path)
    ready = Channel(Nil).new
    done = Channel(Nil).new
    received = Channel(Obsctl::IPC::Request).new(1)
    spawn do
      server.bind
      ready.send(nil)
      client = server.accept
      request = client.read_message.as(Obsctl::IPC::Request)
      received.send(request)
      client.write_message(Obsctl::IPC::Response.new(request.id, true, JSON.parse(%({"message":"scene set"}))))
      client.close
      done.send(nil)
    ensure
      server.close
    end

    ready.receive
    response = Obsctl::TUI::CommandClient.new(path).send(Obsctl::IPC::CommandPayload.new("set_scene", "Main"))
    request = received.receive
    request.id.should start_with("tui-")
    request.command.not_nil!.target.should eq("Main")
    response.result.not_nil!["message"].as_s.should eq("scene set")
    done.receive
  ensure
    server.try(&.close)
  end

  it "gives up on a daemon that accepts the request and never answers" do
    # The dashboard sends commands from its render-loop fiber, so a wait with
    # no deadline is a frozen terminal rather than a slow one.
    path = File.join(Dir.tempdir, "obsctl-tui-command-stuck-#{Random.rand(1_000_000)}.sock")
    server = Obsctl::IPC::UnixServer.new(path)
    ready = Channel(Nil).new
    release = Channel(Nil).new
    spawn do
      server.bind
      ready.send(nil)
      client = server.accept
      client.read_message
      # Deliberately no response: hold the connection open until the spec is
      # done asserting that the client stopped waiting.
      release.receive
      client.close
    rescue
    end

    ready.receive
    client = Obsctl::TUI::CommandClient.new(path, timeout: 200.milliseconds)

    begin
      expect_raises(Obsctl::Domain::RequestTimeout) do
        client.send(Obsctl::IPC::CommandPayload.new("set_scene", "Main"))
      end
    ensure
      release.send(nil)
      server.close
    end
  ensure
    server.try(&.close)
  end
end
