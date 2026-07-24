require "../../src/obsctl/cli/main"

module Obsctl
  module SpecSupport
    # Runs the CLI with captured IO so specs never write to the real STDOUT or
    # STDERR. `Main.run` defaults to the process streams, which makes an
    # otherwise-green suite print daemon and command output between the dots
    # and hides real failures in CI logs.
    module CliCapture
      record Capture, exit_code : Int32, stdout : String, stderr : String

      # Runs the CLI and returns the exit code with both streams captured.
      def self.run(
        args : Array(String),
        service_installer : Service::ServiceInstaller? = nil,
        tui_runner : Proc(String, Int32)? = nil,
      ) : Capture
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        exit_code = CLI::Main.run(args, service_installer, stdout, stderr, tui_runner)
        Capture.new(exit_code, stdout.to_s, stderr.to_s)
      end

      # Runs the CLI and returns only the exit code, discarding both streams.
      def self.exit_code(
        args : Array(String),
        service_installer : Service::ServiceInstaller? = nil,
        tui_runner : Proc(String, Int32)? = nil,
      ) : Int32
        run(args, service_installer, tui_runner).exit_code
      end
    end
  end
end
