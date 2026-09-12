require "../../spec_helper"
require "../../../src/obsctl/runtime/secret_redaction"

describe Obsctl::Runtime::SecretRedaction do
  it "redacts every supported secret shape" do
    cases = {
      "password=hunter2"                                => "password=[redacted]",
      "token: abc123"                                   => "token: [redacted]",
      "secret \"hunter2\""                              => "secret [redacted]",
      "authentication-string equals hunter2"            => "authentication-string equals [redacted]",
      "connect wss://alice:hunter2@example.test/socket" => "connect wss://[redacted]@example.test/socket",
      "AUTH STRING was 'hunter2'"                       => "AUTH STRING was [redacted]",
    }

    cases.each do |message, expected|
      Obsctl::Runtime::SecretRedaction.redact(message).should eq(expected)
    end
  end

  it "returns the original string when no secret markers are present" do
    message = "OBS WebSocket disconnected cleanly"
    redacted = Obsctl::Runtime::SecretRedaction.redact(message)

    redacted.should eq(message)
    redacted.object_id.should eq(message.object_id)
  end
end
