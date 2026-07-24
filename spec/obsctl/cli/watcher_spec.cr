require "json"
require "socket"
require "../../spec_helper"
require "../../../src/obsctl/cli/watcher"
require "../../../src/obsctl/ipc/client_session"

# Feeds a fixed set of messages to the watcher over a real socket pair, so the
# watcher exercises its actual read/decode path rather than a stubbed reader.
private def with_scripted_events(messages : Array(Obsctl::IPC::Message), &)
  local, remote = UNIXSocket.pair
  writer = Obsctl::IPC::ClientSession.new(remote)

  spawn do
    messages.each { |message| writer.write_message(message) }
    writer.close
  end

  yield Obsctl::IPC::ClientSession.new(local)
ensure
  local.close unless local.nil? || local.closed?
  remote.close unless remote.nil? || remote.closed?
end

private def watcher_for(
  session : Obsctl::IPC::ClientSession,
  stdout : IO,
  topics : Array(String) = Obsctl::CLI::Watcher::DEFAULT_TOPICS,
  limit : Int32? = nil,
) : Obsctl::CLI::Watcher
  Obsctl::CLI::Watcher.new(
    "/tmp/obsctl-watch-unused.sock",
    topics,
    stdout,
    limit,
    ->(_path : String, _topics : Array(String)) { session }
  )
end

describe Obsctl::CLI::Watcher do
  describe ".validate_topics!" do
    it "accepts the published topics" do
      Obsctl::CLI::Watcher.validate_topics!(["state", "logs"]).should eq(["state", "logs"])
    end

    it "collapses duplicates" do
      Obsctl::CLI::Watcher.validate_topics!(["state", "state"]).should eq(["state"])
    end

    it "rejects an unknown topic by name" do
      expect_raises(Obsctl::Domain::CommandParseError, /unknown watch topic: scenes/) do
        Obsctl::CLI::Watcher.validate_topics!(["state", "scenes"])
      end
    end

    it "rejects an empty topic list" do
      expect_raises(Obsctl::Domain::CommandParseError, /no topics selected/) do
        Obsctl::CLI::Watcher.validate_topics!([] of String)
      end
    end
  end

  it "writes one JSON object per event, one per line" do
    events = [
      Obsctl::IPC::Event.new("state", JSON.parse(%({"connected":true}))),
      Obsctl::IPC::Event.new("logs", JSON.parse(%({"level":"info","message":"ready"}))),
    ] of Obsctl::IPC::Message

    with_scripted_events(events) do |session|
      stdout = IO::Memory.new
      watcher_for(session, stdout).run.should eq(0)

      lines = stdout.to_s.lines
      lines.size.should eq(2)

      first = JSON.parse(lines[0])
      first["topic"].as_s.should eq("state")
      first["data"]["connected"].as_bool.should be_true

      second = JSON.parse(lines[1])
      second["topic"].as_s.should eq("logs")
      second["data"]["message"].as_s.should eq("ready")
    end
  end

  it "emits a null data field rather than omitting it" do
    events = [Obsctl::IPC::Event.new("events", nil)] of Obsctl::IPC::Message

    with_scripted_events(events) do |session|
      stdout = IO::Memory.new
      watcher_for(session, stdout).run

      parsed = JSON.parse(stdout.to_s.lines[0])
      parsed["topic"].as_s.should eq("events")
      parsed["data"].raw.should be_nil
    end
  end

  it "drops events outside the requested topics" do
    events = [
      Obsctl::IPC::Event.new("state", JSON.parse(%({"n":1}))),
      Obsctl::IPC::Event.new("logs", JSON.parse(%({"n":2}))),
      Obsctl::IPC::Event.new("state", JSON.parse(%({"n":3}))),
    ] of Obsctl::IPC::Message

    with_scripted_events(events) do |session|
      stdout = IO::Memory.new
      watcher_for(session, stdout, topics: ["state"]).run

      lines = stdout.to_s.lines
      lines.size.should eq(2)
      lines.each { |line| JSON.parse(line)["topic"].as_s.should eq("state") }
    end
  end

  it "ignores non-event messages on the subscription" do
    messages = [
      Obsctl::IPC::Response.new("req-1", true, JSON.parse(%({"message":"ok"}))),
      Obsctl::IPC::Event.new("state", JSON.parse(%({"n":1}))),
    ] of Obsctl::IPC::Message

    with_scripted_events(messages) do |session|
      stdout = IO::Memory.new
      watcher_for(session, stdout).run

      stdout.to_s.lines.size.should eq(1)
    end
  end

  it "stops after the configured number of events" do
    events = Array(Obsctl::IPC::Message).new(5) do |index|
      Obsctl::IPC::Event.new("state", JSON.parse(%({"n":#{index}})))
    end

    with_scripted_events(events) do |session|
      stdout = IO::Memory.new
      watcher_for(session, stdout, limit: 2).run.should eq(0)

      stdout.to_s.lines.size.should eq(2)
    end
  end

  it "exits successfully when the daemon closes the stream" do
    with_scripted_events([] of Obsctl::IPC::Message) do |session|
      stdout = IO::Memory.new
      watcher_for(session, stdout).run.should eq(0)
      stdout.to_s.should be_empty
    end
  end

  it "reports the daemon as unavailable when the socket does not exist" do
    watcher = Obsctl::CLI::Watcher.new(
      "/tmp/obsctl-watch-absent-#{Random.rand(1_000_000)}.sock",
      Obsctl::CLI::Watcher::DEFAULT_TOPICS,
      IO::Memory.new
    )

    expect_raises(Obsctl::Domain::ServerUnavailable) { watcher.run }
  end
end
