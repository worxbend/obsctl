require "../../spec_helper"
require "../../../src/obsctl/ipc/protocol"
require "../../../src/obsctl/tui/session"

private def tui_ipc_snapshot(scene = "Main Camera")
  JSON.parse({
    connected:             true,
    obs_studio_version:    "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene:         scene,
    scenes:                [
      {
        name:     "Main Camera",
        alias:    "main",
        shortcut: "1",
        group:    nil,
        active:   scene == "Main Camera",
      },
      {
        name:     "BRB",
        alias:    "brb",
        shortcut: "2",
        group:    nil,
        active:   scene == "BRB",
      },
    ],
    audio_inputs: [
      {
        name:           "Mic/Aux",
        alias:          "mic",
        shortcut:       "m",
        muted:          false,
        volume_mul:     0.7,
        volume_db:      nil,
        volume_percent: 70,
      },
    ],
    last_error: nil,
    updated_at: Time.utc.to_rfc3339,
  }.to_json)
end

describe Obsctl::TUI::IpcSessionClient do
  it "subscribes to server state and forwards TUI commands over IPC" do
    path = File.join(Dir.tempdir, "obsctl-tui-ipc-#{Random.rand(1_000_000)}.sock")
    server = Obsctl::IPC::UnixServer.new(path)
    ready = Channel(Nil).new
    command = Channel(Obsctl::IPC::CommandPayload).new(1)
    done = Channel(Nil).new

    spawn do
      server.bind
      ready.send(nil)
      session = server.accept

      subscribe = session.read_message.as(Obsctl::IPC::Request)
      subscribe.subscribe?.should be_true
      subscribe.topics.should eq(["state", "events", "logs"])
      session.write_message(Obsctl::IPC::Response.new(subscribe.id, true, JSON.parse({"message" => "subscribed"}.to_json)))
      session.write_message(Obsctl::IPC::Event.new("state", tui_ipc_snapshot))

      request = session.read_message.as(Obsctl::IPC::Request)
      command.send(request.command.not_nil!)
      session.write_message(Obsctl::IPC::Response.new(request.id, true, JSON.parse({"message" => "scene set"}.to_json)))
      session.close
      done.send(nil)
    ensure
      server.close
    end

    ready.receive
    config = Obsctl::Config::Config.default
    client = Obsctl::TUI::IpcSessionClient.new(Obsctl::IPC::UnixClient.new(path))
    session = Obsctl::TUI::Session.new(config, "/tmp/obsctl-tui-ipc.yml", ->(_config : Obsctl::Config::Config) {
      client.as(Obsctl::TUI::SessionClient)
    })

    model = session.start
    model.snapshot.try(&.current_scene).should eq("Main Camera")

    result = session.execute_line("/scene main")
    payload = command.receive

    payload.name.should eq("set_scene")
    payload.target.should eq("main")
    result.model.last_result.should eq("scene set: main")
    done.receive
  ensure
    server.try(&.close)
  end
end
