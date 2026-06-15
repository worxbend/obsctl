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
end
