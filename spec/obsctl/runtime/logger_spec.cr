require "../../spec_helper"
require "../../../src/obsctl/runtime/logger"

describe Obsctl::Runtime::LogLevel do
  it "parses supported CLI log levels" do
    Obsctl::Runtime::LogLevel.parse("debug").should eq(Obsctl::Runtime::LogLevel::Debug)
    Obsctl::Runtime::LogLevel.parse("info").should eq(Obsctl::Runtime::LogLevel::Info)
    Obsctl::Runtime::LogLevel.parse("warn").should eq(Obsctl::Runtime::LogLevel::Warn)
    Obsctl::Runtime::LogLevel.parse("warning").should eq(Obsctl::Runtime::LogLevel::Warn)
    Obsctl::Runtime::LogLevel.parse("error").should eq(Obsctl::Runtime::LogLevel::Error)
  end

  it "rejects unsupported CLI log levels" do
    expect_raises(Obsctl::Domain::CommandParseError, "invalid log level: trace") do
      Obsctl::Runtime::LogLevel.parse("trace")
    end
  end
end

describe Obsctl::Runtime::Logger do
  it "filters entries below the configured log level and redacts secrets" do
    path = File.join(Dir.tempdir, "obsctl-logger-spec-#{Random.rand(1_000_000)}.log")
    logger = Obsctl::Runtime::Logger.new(Obsctl::Runtime::LogLevel::Warn, path)

    logger.info("ignored password=secret")
    logger.warn("kept authentication=generated-token")
    logger.error("kept error")

    log = File.read(path)
    log.should_not contain("ignored")
    log.should contain("level=warn")
    log.should contain("authentication=[redacted]")
    log.should contain("level=error")
    log.should_not contain("generated-token")
  ensure
    File.delete(path) if path && File.exists?(path)
  end
end
