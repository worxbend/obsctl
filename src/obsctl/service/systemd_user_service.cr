module Obsctl
  module Service
    # Renders the systemd --user unit that runs `obsctl server --headless`.
    struct SystemdUserService
      SERVICE_NAME = "obsctl.service"

      getter executable_path

      # Creates a unit renderer for an absolute obsctl executable path.
      def initialize(@executable_path : String)
      end

      # Returns the default user service path for the supplied environment.
      def self.default_path(env = ENV) : String
        File.join(home(env), ".config/systemd/user", SERVICE_NAME)
      end

      # Renders the complete service unit file.
      def render : String
        <<-SERVICE
        [Unit]
        Description=obsctl OBS WebSocket control daemon
        After=network.target graphical-session.target
        StartLimitIntervalSec=0

        [Service]
        Type=simple
        ExecStart=#{escaped_executable_path} server --headless
        Restart=on-failure
        RestartSec=10

        [Install]
        WantedBy=graphical-session.target
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
