require "../../spec_helper"
require "../../../src/obsctl/server/log_payload"

describe Obsctl::Server::LogPayload do
  it "builds the documented logs-topic entry" do
    at = Time.utc(2024, 5, 1, 12, 30, 0)
    entry = Obsctl::Server::LogPayload.build("warn", "obs_disconnected", "OBS went away", at)

    entry["level"].as_s.should eq("warn")
    entry["code"].as_s.should eq("obs_disconnected")
    entry["message"].as_s.should eq("OBS went away")
    entry["created_at"].as_s.should eq(at.to_rfc3339)
  end

  # A logs entry is pushed to every subscriber, so redaction has to happen
  # here and not be left to whichever producer built the message.
  it "redacts credentials that leaked into the message" do
    entry = Obsctl::Server::LogPayload.build("error", "command_failed", "connect failed password=supersecret")

    entry["message"].as_s.should_not contain("supersecret")
    entry["message"].as_s.should contain("[redacted]")
  end
end
