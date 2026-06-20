require "../../spec_helper"
require "../../../src/obsctl/server/reconnect_signal"

alias WaitResult = Obsctl::Server::ReconnectSignal::WaitResult

private def receive_signal_result(channel : Channel(WaitResult), timeout : Time::Span = 500.milliseconds) : WaitResult
  select
  when result = channel.receive
    result
  when timeout(timeout)
    raise "timed out waiting for reconnect signal result"
  end
end

# Blocks until the on_waiter_registered probe fires, confirming the spawned
# fiber's waiter is visible to concurrent request/wake/cancel calls.
private def wait_for_waiter_registered(channel : Channel(Nil), timeout : Time::Span = 500.milliseconds) : Nil
  select
  when channel.receive
  when timeout(timeout)
    raise "timed out waiting for waiter registration probe"
  end
end

describe Obsctl::Server::ReconnectSignal do
  # request-before-wait: no probe needed — the request epoch is already set
  # before wait is called, so wait returns immediately without registering.
  it "returns immediately when an explicit request was made before waiting" do
    signal = Obsctl::Server::ReconnectSignal.new

    epoch = signal.request
    started = Time.instant

    result = signal.wait(5.seconds, 0_u64)
    result.should be_a(WaitResult::Requested)
    result.epoch.should eq(epoch)
    (Time.instant - started).should be < 100.milliseconds
  end

  # request-during-wait: uses the probe to guarantee the waiter is registered
  # before calling request, so we test the actual concurrent wake path.
  it "wakes a current waiter when an explicit request is made during wait" do
    signal = Obsctl::Server::ReconnectSignal.new
    registered = Channel(Nil).new(1)
    result = Channel(WaitResult).new(1)

    signal.on_waiter_registered = -> { registered.send(nil) }
    spawn { result.send(signal.wait(5.seconds, 0_u64)) }

    wait_for_waiter_registered(registered)

    epoch = signal.request

    wait_result = receive_signal_result(result)
    wait_result.should be_a(WaitResult::Requested)
    wait_result.epoch.should eq(epoch)
  end

  it "does not let a handled explicit request skip a later retry delay" do
    signal = Obsctl::Server::ReconnectSignal.new
    registered = Channel(Nil).new(1)
    result = Channel(WaitResult).new(1)

    signal.on_waiter_registered = -> { registered.send(nil) }
    spawn { result.send(signal.wait(5.seconds, 0_u64)) }

    wait_for_waiter_registered(registered)

    epoch = signal.request
    first_result = receive_signal_result(result)
    first_result.should be_a(WaitResult::Requested)
    first_result.epoch.should eq(epoch)

    started = Time.instant
    second_result = signal.wait(75.milliseconds, epoch)
    second_result.should be_a(WaitResult::TimedOut)
    second_result.epoch.should eq(epoch)

    (Time.instant - started).should be >= 50.milliseconds
  end

  # internal-wake-during-wait: probe confirms the waiter is registered before
  # wake is sent, so the Interrupted result is a true concurrent wake, not a
  # race with request-before-wait behavior.
  it "interrupts a waiter for an internal wake without advancing the explicit request epoch" do
    signal = Obsctl::Server::ReconnectSignal.new
    registered = Channel(Nil).new(1)
    result = Channel(WaitResult).new(1)

    signal.on_waiter_registered = -> { registered.send(nil) }
    spawn { result.send(signal.wait(5.seconds, 0_u64)) }

    wait_for_waiter_registered(registered)

    signal.wake

    wait_result = receive_signal_result(result)
    wait_result.should be_a(WaitResult::Interrupted)
    wait_result.epoch.should eq(0_u64)
    signal.latest_request_epoch.should eq(0_u64)
  end

  it "does not let an internal wake skip a later unrelated retry delay" do
    signal = Obsctl::Server::ReconnectSignal.new
    registered = Channel(Nil).new(1)
    result = Channel(WaitResult).new(1)

    signal.on_waiter_registered = -> { registered.send(nil) }
    spawn { result.send(signal.wait(5.seconds, 0_u64)) }

    wait_for_waiter_registered(registered)
    signal.wake
    wake_result = receive_signal_result(result)
    wake_result.should be_a(WaitResult::Interrupted)
    wake_result.epoch.should eq(0_u64)

    started = Time.instant
    second_result = signal.wait(75.milliseconds, 0_u64)
    second_result.should be_a(WaitResult::TimedOut)
    second_result.epoch.should eq(0_u64)

    (Time.instant - started).should be >= 50.milliseconds
  end

  # cancel-during-wait: probe confirms the waiter is registered before cancel
  # is sent, so the Cancelled result is a true concurrent cancel wake.
  it "returns Cancelled (not Interrupted) when cancel is called during wait" do
    signal = Obsctl::Server::ReconnectSignal.new
    registered = Channel(Nil).new(1)
    result = Channel(WaitResult).new(1)

    signal.on_waiter_registered = -> { registered.send(nil) }
    spawn { result.send(signal.wait(5.seconds, 0_u64)) }

    wait_for_waiter_registered(registered)

    signal.cancel

    wait_result = receive_signal_result(result)
    wait_result.should be_a(WaitResult::Cancelled)
    wait_result.epoch.should eq(0_u64)
    signal.latest_request_epoch.should eq(0_u64)
  end

  # request-before-wait: multiple requests before any wait call; wait should
  # return Requested with the latest epoch immediately.
  it "returns the latest durable epoch after repeated explicit requests" do
    signal = Obsctl::Server::ReconnectSignal.new

    first_epoch = signal.request
    second_epoch = signal.request
    third_epoch = signal.request

    first_epoch.should eq(1_u64)
    second_epoch.should eq(2_u64)
    third_epoch.should eq(3_u64)

    result = signal.wait(5.seconds, first_epoch)
    result.should be_a(WaitResult::Requested)
    result.epoch.should eq(third_epoch)
    signal.latest_request_epoch.should eq(third_epoch)
  end
end
