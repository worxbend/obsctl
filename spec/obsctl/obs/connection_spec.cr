require "../../spec_helper"
require "../../../src/obsctl/obs/connection"

describe Obsctl::OBS::Connection do
  it "gives up on a peer that accepts the socket but never completes the upgrade" do
    # A plain TCP listener that accepts and then says nothing. The TCP handshake
    # succeeds, so the connect does not fail — it just never finishes, which is
    # what `connect_timeout_ms` exists to bound.
    server = TCPServer.new("127.0.0.1", 0)
    accepted = nil.as(TCPSocket?)
    spawn do
      accepted = server.accept
    rescue
    end

    config = Obsctl::Config::ConnectionConfig.new(
      host: "127.0.0.1",
      port: server.local_address.port,
      connect_timeout_ms: 200
    )

    begin
      started = Time.instant
      expect_raises(Obsctl::Domain::ConnectionFailed, /timed out after 200ms/) do
        Obsctl::OBS::Connection.new(config).connect
      end
      elapsed = Time.instant - started
      elapsed.should be < 3.seconds
    ensure
      accepted.try(&.close) rescue nil
      server.close
    end
  end

  it "reports a refused connection as a domain error" do
    # Bind and immediately close, so the port is almost certainly free and
    # actively refusing rather than silently dropping.
    probe = TCPServer.new("127.0.0.1", 0)
    port = probe.local_address.port
    probe.close

    config = Obsctl::Config::ConnectionConfig.new(
      host: "127.0.0.1",
      port: port,
      connect_timeout_ms: 1_000
    )

    expect_raises(Obsctl::Domain::ConnectionFailed, /failed to connect to OBS WebSocket at 127\.0\.0\.1/) do
      Obsctl::OBS::Connection.new(config).connect
    end
  end
end
