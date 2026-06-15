require "../../spec_helper"
require "../../../src/obsctl/service/service_installer"

private class FakeSystemCommandRunner < Obsctl::Service::SystemCommandRunner
  getter calls = [] of Tuple(String, Array(String))

  def initialize(@status : Process::Status = Process::Status.new(0))
  end

  def run(command : String, args : Array(String)) : Process::Status
    @calls << {command, args}
    @status
  end
end

describe Obsctl::Service::ServiceInstaller do
  it "installs the systemd user service and reloads systemd" do
    dir = File.join(Dir.tempdir, "obsctl-service-spec-#{Random.rand(1_000_000)}")
    service_path = File.join(dir, "obsctl.service")
    runner = FakeSystemCommandRunner.new

    message = Obsctl::Service::ServiceInstaller.new(
      service_path: service_path,
      executable_path: "/tmp/obsctl",
      runner: runner
    ).install

    message.should eq("installed user service: #{service_path}")
    File.read(service_path).should contain("ExecStart=/tmp/obsctl server --headless")
    runner.calls.should eq([{"systemctl", ["--user", "daemon-reload"]}])
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "runs service actions through systemctl user commands" do
    runner = FakeSystemCommandRunner.new
    installer = Obsctl::Service::ServiceInstaller.new(
      service_path: "/tmp/obsctl.service",
      executable_path: "/tmp/obsctl",
      runner: runner
    )

    installer.run("start").should eq("service started")

    runner.calls.should eq([{"systemctl", ["--user", "start", "obsctl.service"]}])
  end

  it "removes the service file and reloads systemd on uninstall" do
    dir = File.join(Dir.tempdir, "obsctl-service-spec-#{Random.rand(1_000_000)}")
    service_path = File.join(dir, "obsctl.service")
    FileUtils.mkdir_p(dir)
    File.write(service_path, "unit")
    runner = FakeSystemCommandRunner.new

    Obsctl::Service::ServiceInstaller.new(
      service_path: service_path,
      executable_path: "/tmp/obsctl",
      runner: runner
    ).uninstall

    File.exists?(service_path).should be_false
    runner.calls.should eq([{"systemctl", ["--user", "daemon-reload"]}])
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "rejects unknown service actions" do
    installer = Obsctl::Service::ServiceInstaller.new(
      service_path: "/tmp/obsctl.service",
      executable_path: "/tmp/obsctl",
      runner: FakeSystemCommandRunner.new
    )

    expect_raises(Obsctl::Domain::CommandParseError, "unknown service action: enable") do
      installer.run("enable")
    end
  end

  it "raises a service error when systemctl fails" do
    installer = Obsctl::Service::ServiceInstaller.new(
      service_path: "/tmp/obsctl.service",
      executable_path: "/tmp/obsctl",
      runner: FakeSystemCommandRunner.new(Process::Status.new(1))
    )

    expect_raises(Obsctl::Domain::ServiceInstallFailed, "systemctl --user start obsctl.service failed") do
      installer.run("start")
    end
  end
end
