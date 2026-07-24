require "json"
require "../../spec_helper"
require "../../../src/obsctl/cli/main"
require "../../../src/obsctl/server/server"
require "../../support/fake_obs_server"
require "../../support/cli_capture"
require "../../../src/obsctl/cli/watcher"

private def with_fake_cli_config(server : Obsctl::SpecSupport::FakeObsServer, &)
  with_fake_cli_config_for(server.config) { |path| yield path }
end

private def with_fake_cli_config_for(config : Obsctl::Config::Config, &)
  path = File.tempname("obsctl-cli-integration", ".yml")
  Obsctl::Config::ConfigWriter.new.write(path, config, backup: false)
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
            exit_code = Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "scene", "2"])
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

  it "uses server.socket_path from config for thin client commands" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    obsctl_server = nil
    begin
      with_cli_runtime do |runtime_dir|
        socket_path = File.join(runtime_dir, "custom", "obsctl.sock")
        config = Obsctl::Config::Config.new(
          server: Obsctl::Config::ServerConfig.new(socket_path: socket_path),
          connection: server.config.connection,
          scenes: server.config.scenes,
          audio: server.config.audio,
          reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
        )
        with_fake_cli_config_for(config) do |path|
          obsctl_server = Obsctl::Server::Server.new(config, path, socket_path: socket_path)
          ready = Channel(Nil).new
          spawn do
            ready.send(nil)
            obsctl_server.not_nil!.run
          end
          ready.receive
          until File.exists?(socket_path)
            Fiber.yield
          end

          exit_code = 1
          20.times do
            exit_code = Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "scene", "2"])
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
            mute_exit_code = Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "mute", "mic"])
            break if mute_exit_code == 0
            sleep 50.milliseconds
          end

          mute_exit_code.should eq(0)
          Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "vol", "desktop", "80"]).should eq(0)

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
            exit_code = Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "dump-config"])
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

  it "returns a config error when server-side dump would create alias conflicts" do
    server = Obsctl::SpecSupport::FakeObsServer.new(
      scenes: ["Main Camera", "BRB"]
    ).start
    obsctl_server = nil
    begin
      config = Obsctl::Config::Config.new(
        connection: server.config.connection,
        scenes: [
          Obsctl::Config::SceneConfig.new("Main Camera", "brb"),
        ],
        reconnect: Obsctl::Config::ReconnectConfig.new(enabled: false)
      )

      with_fake_cli_config_for(config) do |path|
        original = File.read(path)
        with_cli_runtime do
          obsctl_server = start_cli_server(config, path)

          exit_code = 1
          20.times do
            exit_code = Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "dump-config"])
            break if exit_code == 2
            sleep 50.milliseconds
          end

          exit_code.should eq(2)
          File.read(path).should eq(original)
          Dir.glob("#{path}.bak.*").empty?.should be_true
        end
      end
    ensure
      obsctl_server.try(&.stop)
      server.stop if server
    end
  end

  it "drives the full recording lifecycle through the local server IPC path" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    obsctl_server = nil
    begin
      with_fake_cli_config(server) do |path|
        with_cli_runtime do
          obsctl_server = start_cli_server(server.config, path)

          start_exit_code = 1
          20.times do
            start_exit_code = Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "record", "start"])
            break if start_exit_code == 0
            sleep 50.milliseconds
          end

          start_exit_code.should eq(0)
          server.recording?.should be_true
          server.record_paused?.should be_false

          Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "record", "pause"]).should eq(0)
          server.record_paused?.should be_true

          Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "record", "resume"]).should eq(0)
          server.record_paused?.should be_false

          stop = Obsctl::SpecSupport::CliCapture.run(["--config", path, "record", "stop"])
          stop.exit_code.should eq(0)
          stop.stdout.should contain(server.record_output_path)
          server.recording?.should be_false
        end
      end
    ensure
      obsctl_server.try(&.stop)
      server.stop if server
    end
  end

  it "reports record status as human lines and as a JSON envelope" do
    server = Obsctl::SpecSupport::FakeObsServer.new(recording: true).start
    obsctl_server = nil
    begin
      with_fake_cli_config(server) do |path|
        with_cli_runtime do
          obsctl_server = start_cli_server(server.config, path)

          human = Obsctl::SpecSupport::CliCapture.run(["--config", path, "record", "status"])
          20.times do
            break if human.exit_code == 0
            sleep 50.milliseconds
            human = Obsctl::SpecSupport::CliCapture.run(["--config", path, "record", "status"])
          end

          human.exit_code.should eq(0)
          human.stdout.should contain("recording: active")
          human.stdout.should contain("timecode: 00:00:03.000")
          human.stdout.should contain("duration_ms: 3000")

          json = Obsctl::SpecSupport::CliCapture.run(["--config", path, "record", "status", "--json"])
          json.exit_code.should eq(0)
          envelope = JSON.parse(json.stdout.lines[0])
          envelope["ok"].as_bool.should be_true
          envelope["result"]["active"].as_bool.should be_true
          envelope["result"]["paused"].as_bool.should be_false
          envelope["result"]["duration_ms"].as_i64.should eq(3_000)
          envelope["exit_code"].as_i.should eq(0)
        end
      end
    ensure
      obsctl_server.try(&.stop)
      server.stop if server
    end
  end

  it "streams live daemon events as newline-delimited JSON" do
    server = Obsctl::SpecSupport::FakeObsServer.new.start
    obsctl_server = nil
    begin
      with_fake_cli_config(server) do |path|
        with_cli_runtime do
          obsctl_server = start_cli_server(server.config, path)
          socket_path = obsctl_server.not_nil!.socket_path
          stdout = IO::Memory.new

          watcher = Obsctl::CLI::Watcher.new(socket_path, ["state"], stdout, 1)
          done = Channel(Int32).new(1)
          spawn { done.send(watcher.run) }

          # Provoke a state event through a normal command.
          20.times do
            break if Obsctl::SpecSupport::CliCapture.exit_code(["--config", path, "scene", "2"]) == 0
            sleep 50.milliseconds
          end

          select
          when exit_code = done.receive
            exit_code.should eq(0)
          when timeout(5.seconds)
            fail "watcher did not emit a state event"
          end

          lines = stdout.to_s.lines
          lines.size.should eq(1)
          parsed = JSON.parse(lines[0])
          parsed["topic"].as_s.should eq("state")
          parsed["data"].raw.should_not be_nil
        end
      end
    ensure
      obsctl_server.try(&.stop)
      server.stop if server
    end
  end
end
