require "../../spec_helper"
require "../../../src/obsctl/cli/main"

describe Obsctl::CLI::Main do
  it "returns config error for missing config when command requires config" do
    path = "/tmp/obsctl-missing-#{Random.rand(1_000_000)}.yml"
    Obsctl::CLI::Main.run(["--config", path, "validate-config"]).should eq(2)
  end

  it "returns server unavailable for thin client commands when IPC is missing" do
    runtime_dir = File.join(Dir.tempdir, "obsctl-cli-main-#{Random.rand(1_000_000)}")
    previous_runtime_dir = ENV["XDG_RUNTIME_DIR"]?
    ENV["XDG_RUNTIME_DIR"] = runtime_dir

    Obsctl::CLI::Main.run(["status"]).should eq(3)
  ensure
    if previous_runtime_dir
      ENV["XDG_RUNTIME_DIR"] = previous_runtime_dir
    else
      ENV.delete("XDG_RUNTIME_DIR")
    end
    FileUtils.rm_rf(runtime_dir) if runtime_dir
  end

  it "writes safe config warnings without exposing plaintext passwords" do
    config = Obsctl::Config::Config.new(
      connection: Obsctl::Config::ConnectionConfig.new(
        password_env: "",
        password: "super-secret"
      )
    )
    io = IO::Memory.new

    Obsctl::CLI::Main.write_config_warnings(config, io)

    stderr = io.to_s
    stderr.should contain("warning: plaintext connection.password is configured")
    stderr.should_not contain("super-secret")
  end
end
