require "../../spec_helper"
require "../../../src/obsctl/server/client_registry"

describe Obsctl::Server::ClientRegistry do
  it "drops a subscriber that stops reading instead of blocking the broadcaster" do
    # The regression this guards: `broadcast` writes to every subscriber from
    # the caller's fiber, and that caller is usually the OBS supervisor fiber.
    # Without a write deadline, a peer that never reads fills its socket buffer
    # and parks the supervisor forever, which stops OBS event handling,
    # telemetry polling and reconnect for every other client.
    server_side, client_side = UNIXSocket.pair
    registry = Obsctl::Server::ClientRegistry.new
    session = Obsctl::IPC::ClientSession.new(server_side)
    registry.add(session, ["events"])

    begin
      # Big enough that a handful of these overflow the socket buffer, which is
      # what makes the write block in the first place.
      payload = JSON.parse({"blob" => "x" * 64_000}.to_json)

      # `client_side` is deliberately never read from. Each broadcast either
      # succeeds or hits BROADCAST_WRITE_TIMEOUT and evicts the subscriber; the
      # assertion is that this terminates at all.
      100.times do
        break if registry.client_count.zero?
        registry.broadcast("events", payload)
      end

      registry.client_count.should eq(0)
    ensure
      server_side.close rescue nil
      client_side.close rescue nil
    end
  end

  it "keeps a subscriber that drains its socket" do
    server_side, client_side = UNIXSocket.pair
    registry = Obsctl::Server::ClientRegistry.new
    session = Obsctl::IPC::ClientSession.new(server_side)
    registry.add(session, ["events"])

    begin
      registry.broadcast("events", JSON.parse({"ok" => true}.to_json))

      line = client_side.gets
      line.should_not be_nil
      JSON.parse(line.not_nil!)["topic"].as_s.should eq("events")
      registry.client_count.should eq(1)
    ensure
      server_side.close rescue nil
      client_side.close rescue nil
    end
  end
end
