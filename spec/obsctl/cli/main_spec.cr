require "../../spec_helper"
require "../../../src/obsctl/cli/main"

describe Obsctl::CLI::Main do
  it "returns config error for missing config when command requires config" do
    path = "/tmp/obsctl-missing-#{Random.rand(1_000_000)}.yml"
    Obsctl::CLI::Main.run(["--config", path, "validate-config"]).should eq(2)
  end
end
