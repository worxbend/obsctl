require "../../spec_helper"
require "../../../src/obsctl/runtime/reconnect_policy"

private def reconnect_config(**overrides)
  Obsctl::Config::ReconnectConfig.new(**overrides)
end

describe Obsctl::Runtime::ReconnectPolicy do
  it "backs off exponentially up to the configured ceiling" do
    policy = Obsctl::Runtime::ReconnectPolicy.new(
      reconnect_config(initial_delay_ms: 500, max_delay_ms: 2_000, multiplier: 2.0, jitter_ms: 0)
    )

    policy.delay_for(0).should eq(500.milliseconds)
    policy.delay_for(1).should eq(1_000.milliseconds)
    policy.delay_for(2).should eq(2_000.milliseconds)
    policy.delay_for(10).should eq(2_000.milliseconds)
  end

  it "adds jitter within the configured range" do
    # Two instances retrying on the identical schedule arrive at OBS as one
    # burst; the jitter setting exists to spread them out.
    config = reconnect_config(initial_delay_ms: 1_000, max_delay_ms: 1_000, multiplier: 1.0, jitter_ms: 250)

    delays = (0...50).map do |seed|
      Obsctl::Runtime::ReconnectPolicy.new(config, Random.new(seed)).delay_for(0)
    end

    delays.each do |delay|
      delay.should be >= 1_000.milliseconds
      delay.should be < 1_250.milliseconds
    end
    delays.uniq.size.should be > 1
  end

  it "never returns a zero delay" do
    # `initial_delay_ms: 0` with `max_delay_ms: 0` passes validation, and a
    # zero-length wait turns the supervisor's retry loop into a busy spin.
    policy = Obsctl::Runtime::ReconnectPolicy.new(
      reconnect_config(initial_delay_ms: 0, max_delay_ms: 0, multiplier: 1.0, jitter_ms: 0)
    )

    policy.delay_for(0).should eq(Obsctl::Runtime::ReconnectPolicy::MINIMUM_DELAY)
    policy.delay_for(5).should eq(Obsctl::Runtime::ReconnectPolicy::MINIMUM_DELAY)
  end
end
