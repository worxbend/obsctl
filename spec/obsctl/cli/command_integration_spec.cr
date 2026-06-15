require "../../spec_helper"
require "../../../src/obsctl/cli/main"
require "../../../src/obsctl/server/server"
require "../../support/fake_obs_server"

private def with_fake_cli_config(server : Obsctl::SpecSupport::FakeObsServer, &)
  path = File.tempname("obsctl-cli-integration", ".yml")
  Obsctl::Config::ConfigWriter.new.write(path, server.config, backup: false)
  yield path
ensure
  File.delete(path) if path && File.exists?(path)
  Dir.glob("#{path}.bak.*").each { |backup| File.delete(backup) } if path
end

private def with_cli_runtime(&)
  runtime_dir = File.join(Dir.tempdir, "obsctl-cli-integration-#{Random.rand(1_000_000)}")
  previous_runtime_dir = ENV["XDG_RUNTIME_DIR"]?
  ENV["XDG_RUNTIME_DIR"] = runtime_dir
  yield runtime_dir
ensure
  if previous_runtime_dir
    ENV["XDG_RUNTIME_DIR"] = previous_runtime_dir
  else
    ENV.delete("XDG_RUNTIME_DIR")
  end
  FileUtils.rm_rf(runtime_dir) if runtime_dir
end

private def start_cli_server(config : Obsctl::Config::Config, config_path : String) : Obsctl::Server::Server
  server = Obsctl::Server::Server.new(config, config_path)
  ready = Channel(Nil).new

  spawn do
    ready.send(nil)
    server.run
  end

  ready.receive
  until File.exists?(server.socket_path)
    Fiber.yield
  end

  server
end

describe Obsctl::CLI::Main do
  it "executes scene command against fake obs-websocket" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    obsctl_server = nil
    begin
      with_fake_cli_config(server) do |path|
        with_cli_runtime do
          obsctl_server = start_cli_server(server.config, path)

          exit_code = 1
          20.times do
            exit_code = Obsctl::CLI::Main.run(["--config", path, "scene", "2"])
            break if exit_code == 0
            sleep 50.milliseconds
          end

          exit_code.should eq(0)
          server.current_scene.should eq("Screen Share")
        end
      end
    ensure
      obsctl_server.try(&.stop)
      server.stop if server
    end
  end

  it "executes audio commands against fake obs-websocket" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    obsctl_server = nil
    begin
      with_fake_cli_config(server) do |path|
        with_cli_runtime do
          obsctl_server = start_cli_server(server.config, path)

          mute_exit_code = 1
          20.times do
            mute_exit_code = Obsctl::CLI::Main.run(["--config", path, "mute", "mic"])
            break if mute_exit_code == 0
            sleep 50.milliseconds
          end

          mute_exit_code.should eq(0)
          Obsctl::CLI::Main.run(["--config", path, "vol", "desktop", "80"]).should eq(0)

          server.input("Mic/Aux").try(&.muted).should eq(true)
          server.input("Desktop Audio").try(&.volume_mul).should eq(0.8)
        end
      end
    ensure
      obsctl_server.try(&.stop)
      server.stop if server
    end
  end

  it "dumps config through the local server IPC path" do
    server = Obsctl::SpecSupport::FakeObsServer.new(
      inputs: [
        Obsctl::SpecSupport::FakeObsServer::AudioInput.new("Mic/Aux", "input", false, 0.7, -3.0),
        Obsctl::SpecSupport::FakeObsServer::AudioInput.new("Desktop Audio", "output", true, 0.4, -8.0),
        Obsctl::SpecSupport::FakeObsServer::AudioInput.new("Browser Alerts", "input", false, 0.5, -6.0),
      ]
    ).start
    obsctl_server = nil
    begin
      with_fake_cli_config(server) do |path|
        with_cli_runtime do
          obsctl_server = start_cli_server(server.config, path)

          exit_code = 1
          20.times do
            exit_code = Obsctl::CLI::Main.run(["--config", path, "dump-config"])
            break if exit_code == 0
            sleep 50.milliseconds
          end

          exit_code.should eq(0)
          dumped = Obsctl::Config::ConfigLoader.new.load(path)
          dumped.scenes.find { |scene| scene.name == "Main Camera" }.try(&.alias).should eq("main")
          dumped.scenes.find { |scene| scene.name == "BRB" }.should_not be_nil
          dumped.audio.inputs.find { |input| input.name == "Browser Alerts" }.should_not be_nil
          Dir.glob("#{path}.bak.*").empty?.should be_false
        end
      end
    ensure
      obsctl_server.try(&.stop)
      server.stop if server
    end
  end
end
