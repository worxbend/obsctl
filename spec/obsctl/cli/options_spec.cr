require "../../spec_helper"
require "../../../src/obsctl/cli/options"

describe Obsctl::CLI::OptionsParser do
  it "parses the global JSON flag" do
    options = Obsctl::CLI::OptionsParser.new.parse(["--json", "status"])

    options.json.should be_true
    options.command.should eq("status")
    options.args.should be_empty
  end

  it "leaves command-specific flags in args" do
    options = Obsctl::CLI::OptionsParser.new.parse(["--config", "/tmp/config.yml", "watch", "--topics", "logs"])

    options.config_path.should eq("/tmp/config.yml")
    options.command.should eq("watch")
    options.args.should eq(["--topics", "logs"])
  end
end

describe "scene-profile flag forms" do
  # obsctl-rs offers these as flags on one command; obsctl's registry knows
  # only names plus positional arguments, so they are translated before the
  # registry sees them. The point of the specs is that both spellings reach the
  # same command.
  it "turns --off and --clear into the canonical off command" do
    ["--off", "--clear"].each do |flag|
      options = Obsctl::CLI::OptionsParser.new.parse(["scene-profile", flag])
      options.command.should eq("scene-profile-off")
      options.args.should be_empty
    end
  end

  it "turns --delete NAME into the canonical delete command" do
    options = Obsctl::CLI::OptionsParser.new.parse(["scene-profile", "--delete", "streaming"])
    options.command.should eq("scene-profile-delete")
    options.args.should eq(["streaming"])
  end

  it "translates the alias spelling too" do
    Obsctl::CLI::OptionsParser.new.parse(["set-scene-profile", "--off"]).command.should eq("scene-profile-off")
  end

  it "leaves the plain forms alone" do
    bare = Obsctl::CLI::OptionsParser.new.parse(["scene-profile"])
    bare.command.should eq("scene-profile")
    bare.args.should be_empty

    named = Obsctl::CLI::OptionsParser.new.parse(["scene-profile", "streaming"])
    named.command.should eq("scene-profile")
    named.args.should eq(["streaming"])
  end

  it "refuses a flag form that was given the wrong number of arguments" do
    expect_raises(Obsctl::Domain::CommandParseError, /takes no argument/) do
      Obsctl::CLI::OptionsParser.new.parse(["scene-profile", "--off", "streaming"])
    end
    expect_raises(Obsctl::Domain::CommandParseError, /needs a scene profile name/) do
      Obsctl::CLI::OptionsParser.new.parse(["scene-profile", "--delete"])
    end
  end
end
