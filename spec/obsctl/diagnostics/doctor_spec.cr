require "file_utils"
require "json"
require "../../spec_helper"
require "../../../src/obsctl/diagnostics/doctor"
require "../../../src/obsctl/config/config_writer"

private def with_doctor_root(&)
  root = File.join(Dir.tempdir, "obsctl-doctor-#{Random.rand(1_000_000)}")
  FileUtils.mkdir_p(File.join(root, "run"))
  yield root
ensure
  FileUtils.rm_rf(root) if root
end

private def write_doctor_config(root : String, config : Obsctl::Config::Config = Obsctl::Config::Config.default) : String
  path = File.join(root, "config.yml")
  Obsctl::Config::ConfigWriter.new.write(path, config, backup: false)
  path
end

private def healthy_daemon_payload : JSON::Any
  JSON.parse(%({"pid":4242,"obs_connected":true,"reconnecting":false,"last_error":null}))
end

private def run_doctor(
  root : String,
  config_path : String,
  env : Hash(String, String) = {"OBS_WEBSOCKET_PASSWORD" => "secret"},
  daemon : JSON::Any? = healthy_daemon_payload,
  service_path : String? = nil,
) : Array(Obsctl::Diagnostics::Check)
  Obsctl::Diagnostics::Doctor.new(
    config_path,
    File.join(root, "run", "obsctl.sock"),
    env,
    ->(_socket : String) { daemon.as(JSON::Any?) },
    service_path || File.join(root, "obsctl.service")
  ).run
end

private def check_for(checks : Array(Obsctl::Diagnostics::Check), name : String) : Obsctl::Diagnostics::Check
  checks.find!(&.name.== name)
end

describe Obsctl::Diagnostics::Doctor do
  it "reports a fully healthy setup" do
    with_doctor_root do |root|
      path = write_doctor_config(root)
      service_path = File.join(root, "obsctl.service")
      File.write(service_path, "[Unit]\n")

      checks = run_doctor(root, path, service_path: service_path)

      Obsctl::Diagnostics::Doctor.healthy?(checks).should be_true
      checks.none?(&.status.fail?).should be_true
      check_for(checks, "version").detail.should eq("obsctl #{Obsctl::VERSION}")
      check_for(checks, "daemon").detail.should contain("pid 4242")
      check_for(checks, "obs").status.ok?.should be_true
      check_for(checks, "service").status.ok?.should be_true
    end
  end

  it "fails with a remedy when no config file exists" do
    with_doctor_root do |root|
      checks = run_doctor(root, File.join(root, "absent.yml"))

      config = check_for(checks, "config")
      config.status.fail?.should be_true
      config.remedy.should eq("run: obsctl init")
      Obsctl::Diagnostics::Doctor.healthy?(checks).should be_false
    end
  end

  it "fails when the config file exists but does not parse" do
    with_doctor_root do |root|
      path = File.join(root, "config.yml")
      File.write(path, "connection:\n  port: not-a-number\n")

      config = check_for(run_doctor(root, path), "config")
      config.status.fail?.should be_true
      config.remedy.should eq("run: obsctl validate-config")
    end
  end

  it "warns when the password environment variable is unset" do
    with_doctor_root do |root|
      path = write_doctor_config(root)

      credentials = check_for(run_doctor(root, path, env: {} of String => String), "credentials")
      credentials.status.warn?.should be_true
      credentials.detail.should contain("OBS_WEBSOCKET_PASSWORD")
      credentials.remedy.not_nil!.should contain("export OBS_WEBSOCKET_PASSWORD")
    end
  end

  it "warns about a plaintext password without echoing it" do
    with_doctor_root do |root|
      config = Obsctl::Config::Config.new(
        connection: Obsctl::Config::ConnectionConfig.new(password_env: "", password: "hunter2")
      )
      path = write_doctor_config(root, config)

      checks = run_doctor(root, path)
      credentials = check_for(checks, "credentials")
      credentials.status.warn?.should be_true
      credentials.detail.should contain("plaintext")

      checks.each do |check|
        check.detail.should_not contain("hunter2")
        (check.remedy || "").should_not contain("hunter2")
      end
    end
  end

  it "fails with startup guidance when the daemon is not reachable" do
    with_doctor_root do |root|
      path = write_doctor_config(root)

      checks = run_doctor(root, path, daemon: nil)
      daemon = check_for(checks, "daemon")
      daemon.status.fail?.should be_true
      daemon.remedy.not_nil!.should contain("obsctl server --headless")

      obs = check_for(checks, "obs")
      obs.status.warn?.should be_true
      obs.detail.should contain("daemon is not running")
      Obsctl::Diagnostics::Doctor.healthy?(checks).should be_false
    end
  end

  it "fails the obs check when the daemon is up but OBS is disconnected" do
    with_doctor_root do |root|
      path = write_doctor_config(root)
      payload = JSON.parse(%({"pid":7,"obs_connected":false,"reconnecting":false,"last_error":"connection refused"}))

      obs = check_for(run_doctor(root, path, daemon: payload), "obs")
      obs.status.fail?.should be_true
      obs.detail.should eq("connection refused")
      obs.remedy.not_nil!.should contain("obsctl reconnect")
    end
  end

  it "only warns while the daemon is actively reconnecting" do
    with_doctor_root do |root|
      path = write_doctor_config(root)
      payload = JSON.parse(%({"pid":7,"obs_connected":false,"reconnecting":true,"last_error":"retrying"}))

      checks = run_doctor(root, path, daemon: payload)
      check_for(checks, "obs").status.warn?.should be_true
      Obsctl::Diagnostics::Doctor.healthy?(checks).should be_true
    end
  end

  it "treats a missing systemd unit as optional" do
    with_doctor_root do |root|
      path = write_doctor_config(root)

      checks = run_doctor(root, path, service_path: File.join(root, "absent.service"))
      service = check_for(checks, "service")
      service.status.warn?.should be_true
      service.remedy.not_nil!.should contain("optional")
      Obsctl::Diagnostics::Doctor.healthy?(checks).should be_true
    end
  end

  it "serializes every check field for JSON consumers" do
    with_doctor_root do |root|
      path = write_doctor_config(root)

      checks = run_doctor(root, path, daemon: nil)
      parsed = JSON.parse(checks.to_json).as_a
      parsed.size.should eq(checks.size)

      daemon = parsed.find! { |entry| entry["name"].as_s == "daemon" }
      daemon["status"].as_s.should eq("fail")
      daemon["detail"].as_s.should contain("no obsctl daemon is responding")
      daemon["remedy"].as_s.should contain("obsctl server --headless")

      version = parsed.find! { |entry| entry["name"].as_s == "version" }
      version["remedy"].raw.should be_nil
    end
  end
end
