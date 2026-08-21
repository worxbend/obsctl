require "json"
require "./check"
require "../config/config"
require "../config/config_loader"
require "../config/config_schema"
require "../domain/errors"
require "../ipc/protocol"
require "../ipc/socket_path"
require "../service/systemd_user_service"
require "../version"

module Obsctl
  module Diagnostics
    # Collects setup diagnostics for `obsctl doctor`.
    #
    # Every external dependency is injected so the whole report is reproducible
    # in specs without a daemon, a config file, or an OBS instance. The probe
    # returns the daemon's server-status payload, or nil when the daemon is not
    # reachable.
    class Doctor
      alias DaemonProbe = Proc(String, JSON::Any?)

      def initialize(
        @config_path : String,
        @socket_path : String,
        @env : Hash(String, String) | ENV.class = ENV,
        @daemon_probe : DaemonProbe = ->Doctor.probe_daemon(String),
        @service_path : String = Service::SystemdUserService.default_path,
      )
      end

      # Runs every check in report order.
      def run : Array(Check)
        checks = [] of Check
        checks << version_check

        config_checks_result, config = config_checks
        checks.concat(config_checks_result)

        checks.concat(credential_checks(config)) if config
        checks << socket_check

        daemon_check, daemon = daemon_check_and_status
        checks << daemon_check
        checks << obs_check(daemon)
        checks << service_check
        checks
      end

      # True when no check failed. Warnings do not fail the command.
      def self.healthy?(checks : Array(Check)) : Bool
        checks.none?(&.status.fail?)
      end

      # Default probe: asks a running daemon for its status payload.
      def self.probe_daemon(socket_path : String) : JSON::Any?
        client = IPC::UnixClient.new(socket_path)
        request = IPC::Request.new("doctor-000001", IPC::Request::TYPE_COMMAND, IPC::CommandPayload.new("get_server_status"))
        response = client.request(request)
        response.ok ? response.result : nil
      rescue Domain::ObsctlError
        nil
      rescue
        nil
      end

      private def version_check : Check
        Check.ok("version", "obsctl #{Obsctl::VERSION}")
      end

      private def config_checks : Tuple(Array(Check), Config::Config?)
        unless File.file?(@config_path)
          return {
            [Check.fail(
              "config",
              "no config file at #{@config_path}",
              "run: obsctl init"
            )],
            nil,
          }
        end

        config = Config::ConfigLoader.new.load(@config_path)
        checks = [Check.ok("config", "loaded #{@config_path}")]

        warnings = Config::ConfigSchema.warnings(config)
        warnings.each do |warning|
          checks << Check.warn("config.schema", warning)
        end
        checks << Check.ok("config.schema", "no schema warnings") if warnings.empty?

        {checks, config}
      rescue ex
        # Any load failure is a diagnosis, not a crash. A malformed config is
        # precisely the situation the user is running doctor to understand, so
        # this catches parse and cast errors too, not only Domain::ObsctlError.
        {
          [Check.fail(
            "config",
            "#{@config_path} is invalid: #{ex.message}",
            "run: obsctl validate-config"
          )],
          nil,
        }
      end

      # Reports where the OBS password comes from without ever reading it.
      private def credential_checks(config : Config::Config) : Array(Check)
        password = config.connection.password
        env_name = config.connection.password_env

        if password && !password.empty?
          return [Check.warn(
            "credentials",
            "connection.password is stored in plaintext in the config file",
            "move it to an environment variable and set connection.password_env"
          )]
        end

        if env_name.nil? || env_name.empty?
          return [Check.warn(
            "credentials",
            "no password source configured; obsctl will connect without authentication",
            "set connection.password_env if obs-websocket requires a password"
          )]
        end

        if (@env[env_name]? || "").empty?
          return [Check.warn(
            "credentials",
            "connection.password_env is #{env_name}, but that variable is unset or empty",
            "export #{env_name} in the environment that runs the daemon"
          )]
        end

        [Check.ok("credentials", "password read from #{env_name}")]
      end

      private def socket_check : Check
        directory = File.dirname(@socket_path)
        unless File.directory?(directory)
          return Check.warn(
            "socket",
            "socket directory #{directory} does not exist yet",
            "it is created when the daemon starts; run: obsctl server --headless"
          )
        end

        unless File::Info.writable?(directory)
          return Check.fail(
            "socket",
            "socket directory #{directory} is not writable",
            "fix the directory permissions so the daemon can bind its socket"
          )
        end

        Check.ok("socket", @socket_path)
      end

      # Reports whether the daemon answered, and hands back what it said.
      #
      # The status payload is returned as well as checked because `obs_check`
      # reads OBS connectivity out of the same answer, and the daemon should
      # be asked once. Returned as a pair, the way `config_checks` returns its
      # checks with the config it loaded, rather than appended to the caller's
      # array — a method that both fills in a list it was handed and returns a
      # value has to be read twice to see what it did.
      private def daemon_check_and_status : Tuple(Check, JSON::Any?)
        daemon = @daemon_probe.call(@socket_path)

        unless daemon
          return {
            Check.fail(
              "daemon",
              "no obsctl daemon is responding at #{@socket_path}",
              "run: obsctl server --headless (or: obsctl service install)"
            ),
            nil,
          }
        end

        pid = daemon["pid"]?.try(&.as_i64?)
        {Check.ok("daemon", pid ? "running (pid #{pid})" : "running"), daemon}
      end

      private def obs_check(daemon : JSON::Any?) : Check
        unless daemon
          return Check.warn(
            "obs",
            "OBS connectivity is unknown because the daemon is not running",
            "start the daemon, then re-run: obsctl doctor"
          )
        end

        return Check.ok("obs", "connected") if daemon["obs_connected"]?.try(&.as_bool?) == true

        detail = daemon["last_error"]?.try(&.as_s?) || "the daemon is not connected to OBS"
        if daemon["reconnecting"]?.try(&.as_bool?) == true
          return Check.warn("obs", "reconnecting: #{detail}")
        end

        Check.fail(
          "obs",
          detail,
          "confirm OBS is running with obs-websocket 5.x enabled, then: obsctl reconnect"
        )
      end

      private def service_check : Check
        return Check.ok("service", "user unit installed at #{@service_path}") if File.file?(@service_path)

        Check.warn(
          "service",
          "no systemd user unit at #{@service_path}",
          "optional; install with: obsctl service install"
        )
      end
    end
  end
end
