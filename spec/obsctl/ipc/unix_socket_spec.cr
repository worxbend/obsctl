require "../../spec_helper"
require "../../../src/obsctl/ipc/protocol"

describe "IPC Unix socket transport" do
  it "round trips a request and response over a Unix socket" do
    path = File.join(Dir.tempdir, "obsctl-ipc-spec-#{Random.rand(1_000_000)}.sock")
    server = Obsctl::IPC::UnixServer.new(path)
    ready = Channel(Nil).new
    done = Channel(Nil).new

    spawn do
      server.bind
      ready.send(nil)
      session = server.accept
      request = session.read_message.as(Obsctl::IPC::Request)
      session.write_message(Obsctl::IPC::Response.new(request.id, true, JSON.parse(%({"message":"ok"}))))
      session.close
      done.send(nil)
    ensure
      server.close
    end

    ready.receive
    client = Obsctl::IPC::UnixClient.new(path)
    response = client.request(
      Obsctl::IPC::Request.new(
        "req-roundtrip",
        Obsctl::IPC::Request::TYPE_COMMAND,
        Obsctl::IPC::CommandPayload.new("ping")
      )
    )

    response.ok.should be_true
    response.result.not_nil!["message"].as_s.should eq("ok")
    done.receive
  end

  it "removes stale socket files before binding" do
    path = File.join(Dir.tempdir, "obsctl-ipc-stale-#{Random.rand(1_000_000)}.sock")
    File.write(path, "")
    server = Obsctl::IPC::UnixServer.new(path)

    server.bind
    File.exists?(path).should be_true
  ensure
    server.try(&.close)
  end
end
