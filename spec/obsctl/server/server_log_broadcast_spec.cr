require "../../spec_helper"
require "../../../src/obsctl/server/server"

class Obsctl::Server::Server
  def test_broadcast_reconnect_diagnostic(entry : JSON::Any) : Bool
    @diagnostic_log_broadcast.broadcast(entry)
  end

  def test_diagnostic_log_broadcast_idle? : Bool
    @diagnostic_log_broadcast.outstanding == 0
  end
end

private def wait_for_server_log_broadcast(timeout : Time::Span = 3.seconds, &block : -> Bool) : Nil
  deadline = Time.instant + timeout

  until block.call
    raise "timed out waiting for server log broadcast condition" if Time.instant >= deadline
    Fiber.yield
  end
end

describe Obsctl::Server::Server do
  it "does not duplicate a primary reconnect diagnostic through secondary log-topic fanout" do
    socket_path = File.join(Dir.tempdir, "obsctl-server-log-broadcast-#{Random.rand(1_000_000)}.sock")
    log_path = File.join(Dir.tempdir, "obsctl-server-log-broadcast-#{Random.rand(1_000_000)}.log")
    logger = Obsctl::Runtime::Logger.new(Obsctl::Runtime::LogLevel::Warn, log_path)
    server = Obsctl::Server::Server.new(
      Obsctl::Config::Config.default,
      "/tmp/obsctl-server-log-broadcast-spec.yml",
      socket_path: socket_path,
      logger: logger
    )
    code = "obs_reconnect_state_publication_failed"
    message = "OBS reconnect state publication failed: Exception: token: [redacted]"
    entry = JSON.parse({
      level:      "warn",
      code:       code,
      message:    message,
      created_at: Time.utc.to_rfc3339,
    }.to_json)

    logger.warn("#{code} #{message}")
    server.test_broadcast_reconnect_diagnostic(entry).should be_true
    wait_for_server_log_broadcast { server.test_diagnostic_log_broadcast_idle? }

    log = File.read(log_path)
    log.scan(/obs_reconnect_state_publication_failed/).size.should eq(1)
    log.should contain("OBS reconnect state publication failed")
    log.should contain("[redacted]")
  ensure
    File.delete(socket_path) if socket_path && File.exists?(socket_path)
    File.delete(log_path) if log_path && File.exists?(log_path)
  end
end
