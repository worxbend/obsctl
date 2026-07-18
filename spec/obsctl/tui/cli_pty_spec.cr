require "../../spec_helper"
require "../../../src/obsctl/ipc/protocol"
require "../../../src/obsctl/ipc/socket_path"

describe "obsctl TUI CLI PTY" do
  it "subscribes, renders daemon state, accepts q, and restores the terminal" do
    runtime_dir = File.join(Dir.tempdir, "obsctl-tui-pty-#{Random.rand(1_000_000)}")
    previous_runtime = ENV["XDG_RUNTIME_DIR"]?
    ENV["XDG_RUNTIME_DIR"] = runtime_dir
    socket_path = Obsctl::IPC::SocketPath.resolve
    Obsctl::IPC::SocketPath.ensure_parent(socket_path)
    server = Obsctl::IPC::UnixServer.new(socket_path)
    ready = Channel(Nil).new
    topics = Channel(Array(String)).new(1)
    done = Channel(Nil).new(1)

    spawn do
      server.bind
      ready.send(nil)
      session = server.accept
      request = session.read_message.as(Obsctl::IPC::Request)
      topics.send(request.topics)
      session.write_message(Obsctl::IPC::Response.new(request.id, true, JSON.parse(%({"message":"subscribed"}))))
      state = JSON.parse(%({"connected":true,"obs_studio_version":"30.1.0","obs_websocket_version":"5.0.0","current_scene":"Main","scenes":[{"name":"Main","active":true}],"audio_inputs":[{"name":"Mic","muted":false,"volume_percent":80}],"output":{"streaming":false,"recording":false},"last_error":null,"updated_at":"2026-07-18T12:00:00Z"}))
      session.write_message(Obsctl::IPC::Event.new("state", state))
      session.socket.gets
      session.close
      done.send(nil)
    ensure
      server.close
    end

    ready.receive
    output = IO::Memory.new
    error = IO::Memory.new
    input = IO::Memory.new("q")
    source = File.expand_path("../../../src/obsctl.cr", __DIR__)
    command = "crystal run #{Process.quote(source)} -- tui"
    status = Process.run("script", ["--quiet", "--return", "--command", command, "/dev/null"], input: input, output: output, error: error)

    status.success?.should be_true, "TUI PTY failed: #{error}\n#{output}"
    topics.receive.should eq(["state", "events", "logs"])
    output.to_s.should contain("\e[?1049h")
    output.to_s.should contain("\e[?25h\e[?1049l")
    select
    when done.receive
    when timeout(2.seconds)
      fail "TUI did not close its subscription socket"
    end
  ensure
    server.try(&.close)
    if previous_runtime
      ENV["XDG_RUNTIME_DIR"] = previous_runtime
    else
      ENV.delete("XDG_RUNTIME_DIR")
    end
    FileUtils.rm_rf(runtime_dir) if runtime_dir
  end
end
