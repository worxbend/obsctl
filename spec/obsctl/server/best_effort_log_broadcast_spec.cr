require "../../spec_helper"
require "../../../src/obsctl/server/best_effort_log_broadcast"

private def diagnostic_entry(id : Int32 = 1) : JSON::Any
  JSON.parse({
    id:         id,
    level:      "warn",
    message:    "diagnostic",
    created_at: Time.utc.to_rfc3339,
  }.to_json)
end

private def receive_broadcast_probe(channel : Channel(T), timeout : Time::Span = 500.milliseconds) : T forall T
  select
  when value = channel.receive
    value
  when timeout(timeout)
    raise "timed out waiting for best-effort broadcast worker"
  end
end

private def wait_for_broadcast_condition(timeout : Time::Span = 500.milliseconds, &block : -> Bool) : Nil
  deadline = Time.instant + timeout

  until block.call
    raise "timed out waiting for best-effort broadcast condition" if Time.instant >= deadline
    Fiber.yield
  end
end

describe Obsctl::Server::BestEffortLogBroadcast do
  klass = Obsctl::Server::BestEffortLogBroadcast

  it "rejects zero or negative capacity" do
    broadcast = ->(_entry : JSON::Any) { nil }

    expect_raises(ArgumentError, "capacity must be positive") do
      klass.new(broadcast, 0)
    end

    expect_raises(ArgumentError, "capacity must be positive") do
      klass.new(broadcast, -1)
    end
  end

  it "increments outstanding for accepted broadcasts and decrements after the worker finishes" do
    started = Channel(Nil).new(1)
    release = Channel(Nil).new(1)
    helper = klass.new(->(_entry : JSON::Any) {
      started.send(nil)
      release.receive
      nil
    })

    helper.broadcast(diagnostic_entry).should be_true
    helper.outstanding.should eq(1)
    receive_broadcast_probe(started)
    helper.outstanding.should eq(1)

    release.send(nil)

    wait_for_broadcast_condition { helper.outstanding == 0 }
    helper.dropped_count.should eq(0_u64)
  end

  it "contains broadcast exceptions and still decrements outstanding" do
    started = Channel(Nil).new(1)
    helper = klass.new(->(_entry : JSON::Any) {
      started.send(nil)
      raise "subscriber write failed"
    })

    helper.broadcast(diagnostic_entry).should be_true
    helper.outstanding.should eq(1)
    receive_broadcast_probe(started)

    wait_for_broadcast_condition { helper.outstanding == 0 }
    helper.dropped_count.should eq(0_u64)
  end

  it "drops broadcasts while capacity is full and counts the drops" do
    capacity = 2
    started = Channel(Nil).new(capacity)
    release = Channel(Nil).new(capacity)
    helper = klass.new(->(_entry : JSON::Any) {
      started.send(nil)
      release.receive
      nil
    }, capacity)

    helper.broadcast(diagnostic_entry(1)).should be_true
    helper.broadcast(diagnostic_entry(2)).should be_true
    capacity.times { receive_broadcast_probe(started) }
    helper.outstanding.should eq(capacity)

    helper.broadcast(diagnostic_entry(3)).should be_false
    helper.dropped_count.should eq(1_u64)
    helper.broadcast(diagnostic_entry(4)).should be_false
    helper.dropped_count.should eq(2_u64)
    helper.outstanding.should eq(capacity)

    capacity.times { release.send(nil) }
    wait_for_broadcast_condition { helper.outstanding == 0 }
  end

  it "accepts later broadcasts after blocked workers are released" do
    started = Channel(Int64).new(2)
    release = Channel(Nil).new(2)
    helper = klass.new(->(entry : JSON::Any) {
      started.send(entry["id"].as_i64)
      release.receive
      nil
    }, 1)

    helper.broadcast(diagnostic_entry(1)).should be_true
    receive_broadcast_probe(started).should eq(1_i64)
    helper.outstanding.should eq(1)

    helper.broadcast(diagnostic_entry(2)).should be_false
    helper.dropped_count.should eq(1_u64)

    release.send(nil)
    wait_for_broadcast_condition { helper.outstanding == 0 }

    helper.broadcast(diagnostic_entry(3)).should be_true
    receive_broadcast_probe(started).should eq(3_i64)
    helper.outstanding.should eq(1)
    helper.dropped_count.should eq(1_u64)

    release.send(nil)
    wait_for_broadcast_condition { helper.outstanding == 0 }
  end
end
