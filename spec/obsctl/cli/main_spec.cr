require "../../spec_helper"
require "../../../src/obsctl/cli/main"

private class FakeCliSystemCommandRunner < Obsctl::Service::SystemCommandRunner
  getter calls = [] of Tuple(String, Array(String))

  def run(command : String, args : Array(String)) : Process::Status
    @calls << {command, args}
    Process::Status.new(0)
  end
end

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

  it "returns command parse error for unsupported log levels" do
    Obsctl::CLI::Main.run(["--log-level", "trace", "status"]).should eq(5)
  end

  it "smoke tests service install through the CLI boundary" do
    dir = File.join(Dir.tempdir, "obsctl-cli-service-#{Random.rand(1_000_000)}")
    service_path = File.join(dir, "obsctl.service")
    runner = FakeCliSystemCommandRunner.new
    installer = Obsctl::Service::ServiceInstaller.new(
      service_path: service_path,
      executable_path: "/tmp/obsctl",
      runner: runner
    )

    Obsctl::CLI::Main.run(["service", "install"], installer).should eq(0)

    File.read(service_path).should contain("ExecStart=/tmp/obsctl server --headless")
    runner.calls.should eq([{"systemctl", ["--user", "daemon-reload"]}])
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "smoke tests service control through the CLI boundary" do
    runner = FakeCliSystemCommandRunner.new
    installer = Obsctl::Service::ServiceInstaller.new(
      service_path: "/tmp/obsctl.service",
      executable_path: "/tmp/obsctl",
      runner: runner
    )

    Obsctl::CLI::Main.run(["service", "start"], installer).should eq(0)

    runner.calls.should eq([{"systemctl", ["--user", "start", "obsctl.service"]}])
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
