require "../../spec_helper"
require "../../../src/obsctl/domain/command"

describe Obsctl::Domain::Command do
  it "carries the command's name and arguments into the IPC payload" do
    payload = Obsctl::Domain::VolumeCommand.new("Mic", 40).to_payload

    payload.name.should eq(Obsctl::IPC::CommandName::SET_VOLUME)
    payload.target.should eq("Mic")
    payload.percent.should eq(40)
  end

  it "leaves target and percent unset for a command that takes neither" do
    payload = Obsctl::Domain::StatusCommand.new.to_payload

    payload.name.should eq(Obsctl::IPC::CommandName::STATUS)
    payload.target.should be_nil
    payload.percent.should be_nil
  end

  # `help` and `quit` are answered by whichever surface the user typed them
  # on, so asking for their payload is a programming error, not a user one.
  it "refuses to build a payload for a command the daemon never sees" do
    expect_raises(Obsctl::Domain::CommandParseError, "no daemon equivalent") do
      Obsctl::Domain::HelpCommand.new.to_payload
    end
  end
end
