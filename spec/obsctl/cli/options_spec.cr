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
    options = Obsctl::CLI::OptionsParser.new.parse(["--config", "/tmp/config.yml", "server", "--headless"])

    options.config_path.should eq("/tmp/config.yml")
    options.command.should eq("server")
    options.args.should eq(["--headless"])
  end
end
