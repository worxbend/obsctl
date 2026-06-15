require "../../spec_helper"
require "../../../src/obsctl/config/config_writer"

describe Obsctl::Config::ConfigWriter do
  it "backs up existing files when writing defaults over an existing config" do
    dir = "/tmp/obsctl-writer-#{Random.rand(1_000_000)}"
    path = File.join(dir, "config.yml")
    FileUtils.mkdir_p(dir)
    File.write(path, "version: 1\n")

    Obsctl::Config::ConfigWriter.new.write_default(path)

    Dir.glob("#{path}.bak.*").size.should eq(1)
    File.read(path).should contain("connection:")
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
