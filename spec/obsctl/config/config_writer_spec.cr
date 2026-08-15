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

  it "preserves the permissions of the file it replaces" do
    # A config may hold `connection.password` in plaintext, so a user who
    # restricted the file must not have that undone by any rewrite.
    dir = "/tmp/obsctl-writer-#{Random.rand(1_000_000)}"
    path = File.join(dir, "config.yml")
    FileUtils.mkdir_p(dir)
    File.write(path, "version: 1\n")
    File.chmod(path, 0o600)

    Obsctl::Config::ConfigWriter.new.write_default(path)

    File.info(path).permissions.should eq(File::Permissions.new(0o600))
    Dir.glob("#{path}.bak.*").each do |backup|
      File.info(backup).permissions.should eq(File::Permissions.new(0o600))
    end
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "creates a new config owner-readable only" do
    dir = "/tmp/obsctl-writer-#{Random.rand(1_000_000)}"
    path = File.join(dir, "config.yml")

    Obsctl::Config::ConfigWriter.new.write_default(path)

    File.info(path).permissions.should eq(File::Permissions.new(0o600))
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
