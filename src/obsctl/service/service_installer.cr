require "file_utils"
require "./system_command_runner"
require "./systemd_user_service"
require "../domain/errors"

module Obsctl
  module Service
    class ServiceInstaller
      VALID_ACTIONS = %w[install uninstall status start stop restart]

      def initialize(
        @service_path : String = SystemdUserService.default_path,
        @executable_path : String = default_executable_path,
        @runner : SystemCommandRunner = SystemCommandRunner.new,
      )
      end

      def run(action : String) : String
        unless VALID_ACTIONS.includes?(action)
          raise Domain::CommandParseError.new("unknown service action: #{action}")
        end

        case action
        when "install"
          install
        when "uninstall"
          uninstall
        when "status"
          systemctl_service("status")
          "service status shown"
        when "start"
          systemctl_service("start")
          "service started"
        when "stop"
          systemctl_service("stop")
          "service stopped"
        when "restart"
          systemctl_service("restart")
          "service restarted"
        else
          raise Domain::CommandParseError.new("unknown service action: #{action}")
        end
      end

      def install : String
        unit = SystemdUserService.new(File.expand_path(@executable_path)).render
        FileUtils.mkdir_p(File.dirname(@service_path))
        File.write(@service_path, unit)
        systemctl_user(["daemon-reload"])
        "installed user service: #{@service_path}"
      rescue ex : File::Error
        raise Domain::ServiceInstallFailed.new("failed to install service: #{ex.message}")
      end

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
