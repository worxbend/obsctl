require "file_utils"
require "./system_command_runner"
require "./systemd_user_service"
require "../domain/errors"

module Obsctl
  module Service
    # Installs and controls the obsctl systemd user service.
    class ServiceInstaller
      SERVICE_ACTION_MESSAGES = {
        "status"  => "service status shown",
        "start"   => "service started",
        "stop"    => "service stopped",
        "restart" => "service restarted",
      }

      # Creates a service installer with injectable paths and command runner for tests.
      def initialize(
        @service_path : String = SystemdUserService.default_path,
        @executable_path : String = default_executable_path,
        @runner : SystemCommandRunner = SystemCommandRunner.new,
      )
      end

      # Runs a service action such as install, start, status, or uninstall.
      def run(action : String) : String
        return install if action == "install"
        return uninstall if action == "uninstall"

        message = SERVICE_ACTION_MESSAGES[action]?
        raise Domain::CommandParseError.new("unknown service action: #{action}") unless message

        systemctl_service(action)
        message
      end

      # Writes the service unit and reloads the user systemd manager.
      def install : String
        unit = SystemdUserService.new(File.expand_path(@executable_path)).render
        FileUtils.mkdir_p(File.dirname(@service_path))
        File.write(@service_path, unit)
        systemctl_user(["daemon-reload"])
        "installed user service: #{@service_path}"
      rescue ex : File::Error
        raise Domain::ServiceInstallFailed.new("failed to install service: #{ex.message}")
      end

      # Removes the service unit when present and reloads the user systemd manager.
      def uninstall : String
        File.delete(@service_path) if File.exists?(@service_path)
        systemctl_user(["daemon-reload"])
        "uninstalled user service: #{@service_path}"
      rescue ex : File::Error
        raise Domain::ServiceInstallFailed.new("failed to uninstall service: #{ex.message}")
      end

      private def systemctl_service(action : String) : Nil
        systemctl_user([action, SystemdUserService::SERVICE_NAME])
      end

      private def systemctl_user(args : Array(String)) : Nil
        status = @runner.run("systemctl", ["--user"] + args)
        return if status.success?

        raise Domain::ServiceInstallFailed.new("systemctl --user #{args.join(' ')} failed")
      end

      private def default_executable_path : String
        Process.executable_path || PROGRAM_NAME
      end
    end
  end
end
