require "../../spec_helper"
require "../../../src/obsctl/server/reconnect_signal"

private def receive_signal_result(channel : Channel(UInt64), timeout : Time::Span = 500.milliseconds) : UInt64
  select
  when result = channel.receive
    result
  when timeout(timeout)
    raise "timed out waiting for reconnect signal result"
  end
end

private def assert_no_signal_result(channel : Channel(UInt64), timeout : Time::Span) : Nil
  select
  when result = channel.receive
    raise "expected reconnect signal wait to keep blocking, got #{result}"
  when timeout(timeout)
  end
end

describe Obsctl::Server::ReconnectSignal do
  it "returns immediately when an explicit request was made before waiting" do
    signal = Obsctl::Server::ReconnectSignal.new

    epoch = signal.request
    started = Time.instant

    signal.wait(5.seconds, 0_u64).should eq(epoch)
    (Time.instant - started).should be < 100.milliseconds
  end

  it "wakes a current waiter when an explicit request is made" do
    signal = Obsctl::Server::ReconnectSignal.new
    started = Channel(Nil).new(1)
    result = Channel(UInt64).new(1)

    spawn do
      started.send(nil)
      result.send(signal.wait(5.seconds, 0_u64))
    end

    started.receive
    assert_no_signal_result(result, 25.milliseconds)

    epoch = signal.request

    receive_signal_result(result).should eq(epoch)
  end

  it "does not let a handled explicit request skip a later retry delay" do
    signal = Obsctl::Server::ReconnectSignal.new
    result = Channel(UInt64).new(1)

    spawn do
      result.send(signal.wait(5.seconds, 0_u64))
    end

    assert_no_signal_result(result, 25.milliseconds)

    epoch = signal.request
    receive_signal_result(result).should eq(epoch)

    started = Time.instant
    signal.wait(75.milliseconds, epoch).should eq(epoch)

    (Time.instant - started).should be >= 50.milliseconds
  end

  it "interrupts a waiter for an internal wake without advancing the explicit request epoch" do
    signal = Obsctl::Server::ReconnectSignal.new
    result = Channel(UInt64).new(1)

    spawn do
      result.send(signal.wait(5.seconds, 0_u64))
    end

    assert_no_signal_result(result, 25.milliseconds)

    signal.wake

    receive_signal_result(result).should eq(0_u64)
    signal.latest_request_epoch.should eq(0_u64)
  end

  it "does not let an internal wake skip a later unrelated retry delay" do
    signal = Obsctl::Server::ReconnectSignal.new
    result = Channel(UInt64).new(1)

    spawn do
      result.send(signal.wait(5.seconds, 0_u64))
    end

    assert_no_signal_result(result, 25.milliseconds)
    signal.wake
    receive_signal_result(result).should eq(0_u64)

    started = Time.instant
    signal.wait(75.milliseconds, 0_u64).should eq(0_u64)

    (Time.instant - started).should be >= 50.milliseconds
  end

  it "interrupts a waiter on cancel without advancing the explicit request epoch" do
    signal = Obsctl::Server::ReconnectSignal.new
    result = Channel(UInt64).new(1)

    spawn do
      result.send(signal.wait(5.seconds, 0_u64))
    end

    assert_no_signal_result(result, 25.milliseconds)

    signal.cancel

    receive_signal_result(result).should eq(0_u64)
    signal.latest_request_epoch.should eq(0_u64)
  end

  it "returns the latest durable epoch after repeated explicit requests" do
    signal = Obsctl::Server::ReconnectSignal.new

    first_epoch = signal.request
    second_epoch = signal.request
    third_epoch = signal.request

    first_epoch.should eq(1_u64)
    second_epoch.should eq(2_u64)
    third_epoch.should eq(3_u64)
    signal.wait(5.seconds, first_epoch).should eq(third_epoch)
    signal.latest_request_epoch.should eq(third_epoch)
  end
end
