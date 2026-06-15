module Obsctl
  module Service
    struct SystemdUserService
      SERVICE_NAME = "obsctl.service"

      getter executable_path

      def initialize(@executable_path : String)
      end

      def self.default_path(env = ENV) : String
        File.join(home(env), ".config/systemd/user", SERVICE_NAME)
      end

      def render : String
        <<-SERVICE
        [Unit]
        Description=obsctl OBS WebSocket control daemon
        After=graphical-session.target
        Wants=graphical-session.target

        [Service]
        Type=simple
        ExecStart=#{escaped_executable_path} server --headless
        Restart=always
        RestartSec=3

        [Install]
        WantedBy=default.target
        SERVICE
      end

      private def self.home(env) : String
        env["HOME"]? || "."
      end

      private def escaped_executable_path : String
        return executable_path unless executable_path.includes?(' ') || executable_path.includes?('"')

        %("#{executable_path.gsub("\"", "\\\"")}")
      end
    end
  end
end
