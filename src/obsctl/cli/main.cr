require "json"
require "./options"
require "./client_commands"
require "./completions"
require "../config/config_loader"
require "../config/config_writer"
require "../config/config_schema"
require "../domain/command_parser"
require "../domain/command_registry"
require "../domain/local_commands"
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

          # `--quiet` withholds the human rendering only; an explicit `--json`
          # request is the caller asking for output and still gets it.
          effective_stdout = options.quiet && !json_output ? IO::Memory.new : stdout

          dispatch(options, command_args, json_output, service_installer, effective_stdout, stderr, tui_runner)
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

        if options.help || command == "help"
          stdout.puts help_text(options)
          return Domain::ExitCode::Success.value
        end

        if options.version || command == "version"
          write_version(stdout, json_output)
          return Domain::ExitCode::Success.value
        end

        if json_output && !json_command?(command)
          raise Domain::CommandParseError.new(json_unsupported_message(command))
        end

        case command
        when "init"            then run_init(options, stdout)
        when "validate-config" then run_validate_config(options, stdout, stderr, json_output)
        when "doctor"
          expect_arity!("doctor", command_args, 0)
          run_doctor(options.config_path, stdout, json_output)
        when "config"      then run_config(command_args, options, stdout, json_output)
        when "watch"       then run_watch(command_args, options, stdout)
        when "completions" then run_completions(command_args, options, stdout)
        when "server"      then run_server(options, command_args, log_level, stderr)
        when "service"
          run_service(command_args, service_installer, stdout)
        when nil, "tui"
          run_tui(options, command_args, stdout, tui_runner)
        else
          run_client_command(command, command_args, options, stdout, json_output)
        end
      end

      # `run` handles these commands itself instead of sending them to the
      # daemon, so they miss the arity check `CommandRegistry` runs for the
      # rest. The wording of the refusal is public contract, which is why the
      # six local call sites share one place to raise it from.
      private def self.expect_arity!(name : String, args : Array(String), max : Int32) : Nil
        raise Domain::CommandParseError.new("wrong argument count for #{name}") if args.size > max
      end

      private def self.run_init(options : Options, stdout : IO) : Int32
        if File.exists?(options.config_path) && !options.force
          raise Domain::ConfigInvalid.new("config already exists: #{options.config_path}; pass --force to overwrite")
        end
        Config::ConfigWriter.new.write_default(options.config_path)
        stdout.puts "created config: #{options.config_path}"
        Domain::ExitCode::Success.value
      end

      private def self.run_validate_config(options : Options, stdout : IO, stderr : IO, json_output : Bool) : Int32
        config = Config::ConfigLoader.new.load(options.config_path)
        write_config_warnings(config, stderr)
        message = "config valid: #{options.config_path}"
        if json_output
          stdout.puts json_success(message_result(message))
        else
          stdout.puts message
        end
        Domain::ExitCode::Success.value
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
        expect_arity!("service", command_args, 1)

        stdout.puts (service_installer || Service::ServiceInstaller.new).run(action)
        Domain::ExitCode::Success.value
      end

      private def self.run_tui(options : Options, command_args : Array(String), stdout : IO, tui_runner : Proc(String, Int32)?) : Int32
        expect_arity!("tui", command_args, 0)
        socket_path = client_socket_path(options.config_path)
        return tui_runner.call(socket_path) if tui_runner

        config = Config::ConfigLoader.new.load_lenient(options.config_path)
        TUI::App.from_config(config, socket_path: socket_path, output: stdout, config_path: options.config_path).run
      end

      # The thin-client path: everything that becomes a typed IPC command.
      private def self.run_client_command(command : String, command_args : Array(String), options : Options, stdout : IO, json_output : Bool) : Int32
        # argv is already split by the kernel; passing it straight through keeps
        # names containing quotes, tabs, or backslashes intact.
        parsed = Domain::CommandParser.new.parse([command] + command_args)
        client = IPC::UnixClient.new(client_socket_path(options.config_path), timeout: options.timeout)
        client_commands = ClientCommands.new(client, Palette.resolve(options.color, stdout))

        unless json_output
          # `execute` raises on any failure, so reaching here means success.
          stdout.puts client_commands.execute(parsed).message
          return Domain::ExitCode::Success.value
        end

        response = client_commands.request(parsed)
        failure = response.failure
        exit_code = failure ? ClientCommands.exit_code_for(failure).value : Domain::ExitCode::Success.value
        stdout.puts json_envelope(response.ok, response.result, response.error, exit_code)
        exit_code
      end

      # Converts any failure into its canonical exit code and user-facing form.
      private def self.report_failure(ex : Exception, json_output : Bool, stdout : IO, stderr : IO) : Int32
        error = case ex
                when Domain::ObsctlError     then ex
                when OptionParser::Exception then Domain::CommandParseError.new(ex.message || "invalid option")
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
        Watcher.new(
          client_socket_path(options.config_path),
          Watcher.validate_topics!(parse_watch_topics(args)),
          stdout
        ).run
      end

      # Reads the one flag `watch` accepts. The names are not validated here:
      # `Watcher.validate_topics!` owns that, so an empty list still reaches it.
      private def self.parse_watch_topics(args : Array(String)) : Array(String)
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

        topics
      end

      private def self.run_completions(args : Array(String), options : Options, stdout : IO) : Int32
        action = args[0]?
        unless action
          raise Domain::CommandParseError.new("missing shell; expected #{Completions::SHELLS.join(", ")}")
        end

        return run_completion_candidates(args[1..], options, stdout) if action == "candidates"

        expect_arity!("completions", args, 1)
        stdout.puts Completions.render(action)
        Domain::ExitCode::Success.value
      end

      # Lists live OBS names for shell completion, one per line.
      #
      # Runs on every Tab press, so an unreachable daemon prints nothing and
      # still exits 0; a completion helper that fails loudly would spray errors
      # into the user's command line.
      private def self.run_completion_candidates(args : Array(String), options : Options, stdout : IO) : Int32
        kind = args[0]?
        unless kind
          raise Domain::CommandParseError.new("missing kind; expected #{Completions::CANDIDATE_KINDS.join(", ")}")
        end
        expect_arity!("completions candidates", args, 1)

        Completions.candidates(kind, completion_snapshot(options)).each { |name| stdout.puts name }
        Domain::ExitCode::Success.value
      end

      private def self.completion_snapshot(options : Options) : JSON::Any?
        client = IPC::UnixClient.new(
          client_socket_path(options.config_path),
          timeout: options.timeout || COMPLETION_TIMEOUT
        )
        response = ClientCommands.new(client).request(Domain::ObsStatusCommand.new)
        response.ok ? response.result : nil
      rescue Domain::ObsctlError
        nil
      end

      # Completion must never make the shell feel stuck.
      COMPLETION_TIMEOUT = 2.seconds

      # The registry declares these once; `run_config` routes them.
      CONFIG_ACTIONS = Domain::LocalCommands.subcommands_for("config")

      private def self.run_config(args : Array(String), options : Options, stdout : IO, json_output : Bool) : Int32
        action = args[0]?
        raise Domain::CommandParseError.new("missing config action; expected #{CONFIG_ACTIONS.join(", ")}") unless action

        flags = args[1..]
        dry_run = flags.includes?("--dry-run")
        surplus = flags.reject { |flag| flag == "--dry-run" }
        expect_arity!("config #{action}", surplus, 0)
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
          stdout.puts json_success(JSON.parse({"entries" => entries}.to_json))
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
          stdout.puts json_success(JSON.parse(result.to_json))
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
          stdout.puts json_success(JSON.parse(migration.to_json))
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
          stdout.puts json_success(result)
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

      private def self.help_text(options : Options) : String
        daemon = Domain::CommandRegistry.help_lines(Domain::CommandSurface::Cli)
        local = Domain::LocalCommands.help_lines

        String.build do |io|
          io << options.help_text << "\n\n"
          io << "Daemon commands:\n"
          daemon.each { |line| io << "  " << line << "\n" }
          io << "\nLocal commands:\n"
          local.each { |line| io << "  " << line << "\n" }
          io << "\nNames accept an alias, a shortcut, or the exact OBS name."
        end
      end

      private def self.json_command?(command : String?) : Bool
        return false unless command

        Domain::LocalCommands.json?(command) || Domain::CommandRegistry.json?(command)
      end

      private def self.json_unsupported_message(command : String?) : String
        name = command || "status"
        "JSON output is not supported for command: #{name}"
      end

      # A config that cannot be read must not stop a client from talking to a
      # daemon that is running: the default location is the daemon's default
      # too, so it is the best guess available.
      private def self.client_socket_path(config_path : String) : String
        IPC::SocketPath.resolve(Config::ConfigLoader.new.load_lenient(config_path).server.socket_path)
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

      # The envelope for a command that succeeded. Every one of them exits 0
      # and carries no error, so the result is all that differs between them.
      private def self.json_success(result : JSON::Any) : String
        json_envelope(true, result, nil, Domain::ExitCode::Success.value)
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
