require "../../spec_helper"

describe Obsctl::Domain::CommandParser do
  parser = Obsctl::Domain::CommandParser.new

  it "parses quoted scene names" do
    command = parser.parse(%(/scene "Main Camera"))
    command.should be_a(Obsctl::Domain::SetSceneCommand)
    command.as(Obsctl::Domain::SetSceneCommand).target.should eq("Main Camera")
  end

  it "validates volume range" do
    expect_raises(Obsctl::Domain::CommandParseError) do
      parser.parse("/vol mic 101")
    end
  end

  it "parses server status commands" do
    parser.parse("/server-status").should be_a(Obsctl::Domain::ServerStatusCommand)
  end

  it "parses server-side maintenance commands" do
    parser.parse("/obs-status").should be_a(Obsctl::Domain::ObsStatusCommand)
    parser.parse("/validate-config").should be_a(Obsctl::Domain::ValidateConfigCommand)
    parser.parse("/reconnect").should be_a(Obsctl::Domain::ReconnectCommand)
    parser.parse("/shutdown-server").should be_a(Obsctl::Domain::ShutdownServerCommand)
  end

  it "parses stream and recording toggles without arguments" do
    parser.parse("/stream").should be_a(Obsctl::Domain::ToggleStreamCommand)
    parser.parse("/rec").should be_a(Obsctl::Domain::ToggleRecordCommand)
    parser.parse("record").should be_a(Obsctl::Domain::ToggleRecordCommand)
    expect_raises(Obsctl::Domain::CommandParseError) { parser.parse("/stream now") }
  end

  it "parses profile and scene collection targets" do
    parser.parse(%(/profile "Live Profile")).as(Obsctl::Domain::SetProfileCommand).target.should eq("Live Profile")
    parser.parse(%(/collection "Gaming Collection")).as(Obsctl::Domain::SetSceneCollectionCommand).target.should eq("Gaming Collection")
    parser.parse(%(/scene-collection Podcast)).should be_a(Obsctl::Domain::SetSceneCollectionCommand)
  end

  it "parses command names case-insensitively" do
    parser.parse(%(/SCENE "Main Camera")).as(Obsctl::Domain::SetSceneCommand).target.should eq("Main Camera")
    parser.parse("/MUTE mic").should be_a(Obsctl::Domain::MuteCommand)
  end

  it "matches Rust slash stripping and preserves backslashes outside quotes" do
    parser.parse("///HELP").should be_a(Obsctl::Domain::HelpCommand)
    command = parser.parse(%q(scene Camera\One)).as(Obsctl::Domain::SetSceneCommand)
    command.target.should eq(%q(Camera\One))
  end

  it "rejects unsafe or oversized target tokens" do
    expect_raises(Obsctl::Domain::CommandParseError, /control characters/) { parser.parse("/scene main\u0000cam") }
    long_target = "a" * (Obsctl::Domain::CommandParser::MAX_TARGET_TOKEN_LENGTH + 1)
    expect_raises(Obsctl::Domain::CommandParseError, /at most 256/) { parser.parse("/scene #{long_target}") }
  end

  it "rejects quoted volume percentages like the Rust parser" do
    expect_raises(Obsctl::Domain::CommandParseError, /must not be quoted/) { parser.parse(%(/vol mic "50")) }
  end
end
