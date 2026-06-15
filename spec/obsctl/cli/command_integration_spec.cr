require "../../spec_helper"
require "../../../src/obsctl/cli/main"
require "../../support/fake_obs_server"

private def with_fake_cli_config(server : Obsctl::SpecSupport::FakeObsServer, &)
  path = File.tempname("obsctl-cli-integration", ".yml")
  Obsctl::Config::ConfigWriter.new.write(path, server.config, backup: false)
  yield path
ensure
  File.delete(path) if path && File.exists?(path)
end

describe Obsctl::CLI::Main do
  it "executes scene command against fake obs-websocket" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    begin
      with_fake_cli_config(server) do |path|
        Obsctl::CLI::Main.run(["--config", path, "scene", "2"]).should eq(0)
        server.current_scene.should eq("Screen Share")
      end
    ensure
      server.stop if server
    end
  end

  it "executes audio commands against fake obs-websocket" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    begin
      with_fake_cli_config(server) do |path|
        Obsctl::CLI::Main.run(["--config", path, "mute", "mic"]).should eq(0)
        Obsctl::CLI::Main.run(["--config", path, "volume", "desktop", "80"]).should eq(0)

        server.input("Mic/Aux").try(&.muted).should eq(true)
        server.input("Desktop Audio").try(&.volume_mul).should eq(0.8)
      end
    ensure
      server.stop if server
    end
  end
end
