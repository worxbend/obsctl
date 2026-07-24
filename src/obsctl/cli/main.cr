require "json"
require "./options"
require "./command_router"
require "./client_commands"
require "../config/config_loader"
require "../config/config_writer"
require "../config/config_schema"
require "../domain/command_parser"
require "../domain/errors"
require "../ipc/socket_path"
require "../runtime/logger"
require "../server/server"
require "../server/server_options"
require "../service/service_installer"
require "../tui/app"
require "../version"
require "../diagnostics/doctor"
require "../config/config_inspector"
require "./watcher"

module Obsctl
  module CLI
    module Main
      # Entry point. `run` is only the error boundary: it resolves options,
      # delegates to `dispatch`, and converts any failure into the canonical
      # exit code plus either a JSON envelope or a human diagnostic on stderr.
      def self.run(
        argv : Array(String),
        service_installer : Service::ServiceInstaller? = nil,
        stdout : IO = STDOUT,
        stderr : IO = STDERR,
        tui_runner : Proc(String, Int32)? = nil,
      ) : Int32
        json_output = argv.includes?("--json")

        begin
          options = OptionsParser.new.parse(argv)
          command_args, command_json = split_json_flag(options.args)
          json_output = options.json || command_json

          dispatch(options, command_args, json_output, service_installer, stdout, stderr, tui_runner)
        rescue ex
          report_failure(ex, json_output, stdout, stderr)
        end
      end

      # Routes one resolved invocation to its handler.
      private def self.dispatch(
        options : Options,
        command_args : Array(String),
        json_output : Bool,
        service_installer : Service::ServiceInstaller?,
        stdout : IO,
        stderr : IO,
        tui_runner : Proc(String, Int32)?,
      ) : Int32
        command = options.command
        log_level = Runtime::LogLevel.parse(options.log_level)

        if options.version || command == "version"
          write_version(stdout, json_output)
          return 0
        end

        if json_output && !json_command?(command)
          raise Domain::CommandParseError.new(json_unsupported_message(command))
        end

        case command
        when "init"            then run_init(options, stdout)
        when "validate-config" then run_validate_config(options, stdout, stderr, json_output)
        when "doctor"
          raise Domain::CommandParseError.new("wrong argument count for doctor") unless command_args.empty?
          run_doctor(options.config_path, stdout, json_output)
        when "config" then run_config(command_args, options, stdout, json_output)
        when "watch"  then run_watch(command_args, options, stdout)
        when "server" then run_server(options, command_args, log_level, stderr)
        when "service"
          run_service(command_args, service_installer, stdout)
        when nil, "tui"
          run_tui(options, command_args, stdout, tui_runner)
        else
          run_client_command(command, command_args, options, stdout, json_output)
        end
      end

      private def self.run_init(options : Options, stdout : IO) : Int32
        if File.exists?(options.config_path) && !options.force
          raise Domain::ConfigInvalid.new("config already exists: #{options.config_path}; pass --force to overwrite")
        end
        Config::ConfigWriter.new.write_default(options.config_path)
        stdout.puts "created config: #{options.config_path}"
        0
      end

      private def self.run_validate_config(options : Options, stdout : IO, stderr : IO, json_output : Bool) : Int32
        config = Config::ConfigLoader.new.load(options.config_path)
        write_config_warnings(config, stderr)
        message = "config valid: #{options.config_path}"
        if json_output
          stdout.puts json_envelope(true, message_result(message), nil, Domain::ExitCode::Success.value)
        else
          stdout.puts message
        end
        0
      end

      private def self.run_server(options : Options, command_args : Array(String), log_level : Runtime::LogLevel, stderr : IO) : Int32
        config = load_server_config(options.config_path, stderr)
        server_options = Server::ServerOptions.new(headless: command_args.includes?("--headless"))
        socket_path = IPC::SocketPath.resolve(config.server.socket_path)
        logger = Runtime::Logger.new(log_level, output: stderr)
        Server::Server.new(config, options.config_path, server_options, socket_path, logger).run
      end

      private def self.run_service(command_args : Array(String), service_installer : Service::ServiceInstaller?, stdout : IO) : Int32
        action = command_args[0]? || raise Domain::CommandParseError.new("missing service action")
        raise Domain::CommandParseError.new("wrong argument count for service") if command_args.size > 1

        stdout.puts (service_installer || Service::ServiceInstaller.new).run(action)
        0
      end

      private def self.run_tui(options : Options, command_args : Array(String), stdout : IO, tui_runner : Proc(String, Int32)?) : Int32
        raise Domain::CommandParseError.new("wrong argument count for tui") unless command_args.empty?
        socket_path = client_socket_path(options.config_path)
        return tui_runner.call(socket_path) if tui_runner

        # The thin TUI needs local appearance/socket settings, but must not
        # require the daemon's OBS password environment to be present.
        config = File.exists?(options.config_path) ? Config::Config.from_yaml(File.read(options.config_path)) : Config::Config.default
        TUI::App.from_config(config, socket_path: socket_path, output: stdout, config_path: options.config_path).run
      end

      # The thin-client path: everything that becomes a typed IPC command.
      private def self.run_client_command(command : String, command_args : Array(String), options : Options, stdout : IO, json_output : Bool) : Int32
        parsed = Domain::CommandParser.new.parse(cli_to_palette(command, command_args))
        client_commands = ClientCommands.new(IPC::UnixClient.new(client_socket_path(options.config_path)))

        unless json_output
          result = client_commands.execute(parsed)
          stdout.puts result.message
          return result.ok ? 0 : 1
        end

        response = client_commands.request(parsed)
        response_error = response.error
        exit_code = if response.ok
                      Domain::ExitCode::Success.value
                    elsif response_error
                      ClientCommands.exit_code_for(response_error).value
                    else
                      raise Domain::IpcProtocolError.new("server returned an invalid error response")
                    end
        stdout.puts json_envelope(response.ok, response.result, response.error, exit_code)
        exit_code
      end

      # Converts any failure into its canonical exit code and user-facing form.
      private def self.report_failure(ex : Exception, json_output : Bool, stdout : IO, stderr : IO) : Int32
        error = case ex
                when Domain::ObsctlError     then ex
                when OptionParser::Exception then Domain::CommandParseError.new(ex.message || "invalid option")
                else                              nil
                end

        unless error
          if json_output
            write_json_error(stdout, IPC::ErrorPayload.server_error, Domain::ExitCode::Failure.value)
          else
            stderr.puts ex.message
          end
          return Domain::ExitCode::Failure.value
        end

        if json_output
          write_json_error(stdout, IPC::ErrorPayload.from_exception(error), error.exit_code.value)
        elsif error.is_a?(Domain::ServerUnavailable)
          # The startup hint is more useful here than the bare message.
          stderr.puts server_unavailable_message
        else
          stderr.puts error.message
        end

        error.exit_code.value
      end

      # `watch` always writes newline-delimited JSON, so `--json` is accepted
      # for consistency with the other scriptable commands but changes nothing.
      private def self.run_watch(args : Array(String), options : Options, stdout : IO) : Int32
        topics = Watcher::DEFAULT_TOPICS
        index = 0

        while index < args.size
          case arg = args[index]
          when "--topics"
            index += 1
            value = args[index]? || raise Domain::CommandParseError.new("--topics requires a comma-separated list")
            topics = value.split(',').map(&.strip).reject(&.empty?)
          else
            raise Domain::CommandParseError.new("unexpected argument for watch: #{arg}")
          end
          index += 1
        end

        Watcher.new(
          client_socket_path(options.config_path),
          Watcher.validate_topics!(topics),
          stdout
        ).run
      end

      CONFIG_ACTIONS = ["explain", "diff", "migrate"]

      private def self.run_config(args : Array(String), options : Options, stdout : IO, json_output : Bool) : Int32
        action = args[0]?
        raise Domain::CommandParseError.new("missing config action; expected #{CONFIG_ACTIONS.join(", ")}") unless action

        flags = args[1..]
        dry_run = flags.includes?("--dry-run")
        surplus = flags.reject { |flag| flag == "--dry-run" }
        raise Domain::CommandParseError.new("wrong argument count for config #{action}") unless surplus.empty?
        if dry_run && action != "migrate"
          raise Domain::CommandParseError.new("--dry-run is only supported for config migrate")
        end

        case action
        when "explain" then run_config_explain(options.config_path, stdout, json_output)
        when "diff"    then run_config_diff(options.config_path, stdout, json_output)
        when "migrate" then run_config_migrate(options.config_path, stdout, json_output, dry_run)
        else                raise Domain::CommandParseError.new("unknown config action: #{action}; expected #{CONFIG_ACTIONS.join(", ")}")
        end
      end

      private def self.run_config_explain(config_path : String, stdout : IO, json_output : Bool) : Int32
        entries = Config::ConfigInspector.explain(config_path)

        if json_output
          stdout.puts json_envelope(true, JSON.parse({"entries" => entries}.to_json), nil, Domain::ExitCode::Success.value)
        else
          width = entries.max_of?(&.key.size) || 0
          entries.each do |entry|
            stdout.puts "#{entry.key.ljust(width)}  #{entry.value}  (#{entry.source.label})"
          end
        end

        Domain::ExitCode::Success.value
      end

      private def self.run_config_diff(config_path : String, stdout : IO, json_output : Bool) : Int32
        changes = Config::ConfigInspector.diff(config_path)

        if json_output
          result = {"changed" => !changes.empty?, "changes" => changes}
          stdout.puts json_envelope(true, JSON.parse(result.to_json), nil, Domain::ExitCode::Success.value)
        elsif changes.empty?
          stdout.puts "config matches defaults: #{config_path}"
        else
          changes.each do |change|
            stdout.puts "#{change.key}: #{change.default_value || "-"} -> #{change.current_value || "-"}"
          end
        end

        Domain::ExitCode::Success.value
      end

      private def self.run_config_migrate(config_path : String, stdout : IO, json_output : Bool, dry_run : Bool) : Int32
        migration = Config::ConfigInspector.migrate(config_path, dry_run: dry_run)

        if json_output
          stdout.puts json_envelope(true, JSON.parse(migration.to_json), nil, Domain::ExitCode::Success.value)
          return Domain::ExitCode::Success.value
        end

        unless migration.changed
          stdout.puts "config already matches the current schema: #{config_path}"
          return Domain::ExitCode::Success.value
        end

        migration.dropped_keys.each { |key| stdout.puts "drop: #{key}" }
        migration.added_keys.each { |key| stdout.puts "add: #{key}" }
        if dry_run
          stdout.puts "dry run: #{config_path} left unchanged"
        else
          stdout.puts "migrated: #{config_path}"
          stdout.puts "backup: #{migration.backup_path}" if migration.backup_path
        end

        Domain::ExitCode::Success.value
      end

      # Runs every diagnostic and reports them as aligned human lines or as a
      # JSON envelope whose result carries the full check list.
      private def self.run_doctor(config_path : String, stdout : IO, json_output : Bool) : Int32
        checks = Diagnostics::Doctor.new(config_path, client_socket_path(config_path)).run
        healthy = Diagnostics::Doctor.healthy?(checks)
        exit_code = healthy ? Domain::ExitCode::Success.value : Domain::ExitCode::Failure.value

        if json_output
          result = JSON.parse({"healthy" => healthy, "checks" => checks}.to_json)
          stdout.puts json_envelope(healthy, result, nil, exit_code)
        else
          width = checks.max_of?(&.name.size) || 0
          checks.each do |check|
            stdout.puts "[#{check.status.label.ljust(4)}] #{check.name.ljust(width)}  #{check.detail}"
            stdout.puts "#{" " * (width + 9)}-> #{check.remedy}" if check.remedy
          end
        end

        exit_code
      end

      private def self.write_version(stdout : IO, json_output : Bool) : Nil
        if json_output
          result = JSON.parse({"version" => Obsctl::VERSION}.to_json)
          stdout.puts json_envelope(true, result, nil, Domain::ExitCode::Success.value)
        else
          stdout.puts "obsctl #{Obsctl::VERSION}"
        end
      end

      private def self.load_server_config(config_path : String, stderr : IO) : Config::Config
        unless File.exists?(config_path)
          stderr.puts "obsctl: no config at #{config_path}, creating default"
          Config::ConfigWriter.new.write_default(config_path)
          return Config::Config.default
        end
        Config::ConfigLoader.new.load(config_path)
      rescue ex : Domain::ObsctlError
        stderr.puts "obsctl: config error (#{ex.message}), using defaults"
        Config::Config.default
      rescue ex
        stderr.puts "obsctl: failed to load config (#{ex.message}), using defaults"
        Config::Config.default
      end

      private def self.split_json_flag(args : Array(String)) : Tuple(Array(String), Bool)
        json = false
        filtered = args.reject do |arg|
          if arg == "--json"
            json = true
            true
          else
            false
          end
        end
        {filtered, json}
      end

      private def self.json_command?(command : String?) : Bool
        case command
        when "status", "obs-status", "server-status", "reconnect", "shutdown-server",
             "scene", "mute", "unmute", "toggle-mute", "vol", "volume",
             "profile", "collection", "scene-collection",
             "stream", "rec", "record",
             "dump-config", "reload-config", "validate-config", "doctor", "config", "watch"
          true
        else
          false
        end
      end

      private def self.json_unsupported_message(command : String?) : String
        name = command || "status"
        "JSON output is not supported for command: #{name}"
      end

      private def self.cli_to_palette(command : String, args : Array(String)) : String
        case command
        when "scene"
          "/scene #{quote_arg(args[0]?)}"
        when "profile"
          "/profile #{quote_arg(args[0]?)}"
        when "collection", "scene-collection"
          "/collection #{quote_arg(args[0]?)}"
        when "mute"
          "/mute #{quote_arg(args[0]?)}"
        when "unmute"
          "/unmute #{quote_arg(args[0]?)}"
        when "toggle-mute"
          "/toggle-mute #{quote_arg(args[0]?)}"
        when "volume"
          "/vol #{quote_arg(args[0]?)} #{quote_arg(args[1]?)}"
        when "vol"
          "/vol #{quote_arg(args[0]?)} #{quote_arg(args[1]?)}"
        when "status"
          "/status"
        when "server-status"
          "/server-status"
        when "obs-status"
          "/obs-status"
        when "validate-config"
          "/validate-config"
        when "reconnect"
          "/reconnect"
        when "shutdown-server"
          "/shutdown-server"
        when "dump-config"
          "/dump-config"
        else
          "/#{command} #{args.map { |arg| quote_arg(arg) }.join(" ")}"
        end.strip
      end

      private def self.quote_arg(value : String?) : String
        raise Domain::CommandParseError.new("missing argument") unless value
        if value.includes?(' ')
          %("#{value.gsub("\"", "\\\"")}")
        else
          value
        end
      end

      private def self.client_socket_path(config_path : String) : String
        return IPC::SocketPath.resolve unless File.exists?(config_path)

        config = Config::Config.from_yaml(File.read(config_path))
        IPC::SocketPath.resolve(config.server.socket_path)
      rescue
        IPC::SocketPath.resolve
      end

      def self.write_config_warnings(config : Config::Config, io : IO = STDERR) : Nil
        Config::ConfigSchema.warnings(config).each do |warning|
          io.puts "warning: #{warning}"
        end
      end

      private def self.server_unavailable_message : String
        "obsctl server is not running.\n" \
        "Start it with:\n" \
        "  obsctl server --headless\n" \
        "Or install service:\n" \
        "  obsctl service install\n" \
        "  systemctl --user enable --now obsctl.service"
      end

      private def self.message_result(message : String) : JSON::Any
        JSON.parse({"message" => message}.to_json)
      end

      private def self.write_json_error(stdout : IO, error : IPC::ErrorPayload, exit_code : Int32) : Nil
        stdout.puts json_envelope(false, nil, error, exit_code)
      end

      private def self.json_envelope(ok : Bool, result : JSON::Any?, error : IPC::ErrorPayload?, exit_code : Int32) : String
        JSON.build do |json|
          json.object do
            json.field "ok", ok
            json.field "result" do
              if result
                result.to_json(json)
              else
                json.null
              end
            end
            json.field "error" do
              if error
                error.to_json(json)
              else
                json.null
              end
            end
            json.field "exit_code", exit_code
          end
        end
      end
    end
  end
end
