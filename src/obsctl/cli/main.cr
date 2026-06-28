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

module Obsctl
  module CLI
    module Main
      def self.run(
        argv : Array(String),
        service_installer : Service::ServiceInstaller? = nil,
        stdout : IO = STDOUT,
        stderr : IO = STDERR,
      ) : Int32
        json_output = argv.includes?("--json")

        begin
          options = OptionsParser.new.parse(argv)
          command = options.command
          command_args, command_json = split_json_flag(options.args)
          json_output = options.json || command_json
          log_level = Runtime::LogLevel.parse(options.log_level)

          if json_output && !json_command?(command)
            raise Domain::CommandParseError.new(json_unsupported_message(command))
          end

          if command == "init"
            if File.exists?(options.config_path) && !options.force
              raise Domain::ConfigInvalid.new("config already exists: #{options.config_path}; pass --force to overwrite")
            end
            Config::ConfigWriter.new.write_default(options.config_path)
            stdout.puts "created config: #{options.config_path}"
            return 0
          end

          if command == "validate-config"
            config = Config::ConfigLoader.new.load(options.config_path)
            write_config_warnings(config, stderr)
            message = "config valid: #{options.config_path}"
            if json_output
              stdout.puts json_envelope(true, message_result(message), nil, Domain::ExitCode::Success.value)
            else
              stdout.puts message
            end
            return 0
          end

          if command == "server"
            config = load_server_config(options.config_path, stderr)
            server_options = Server::ServerOptions.new(headless: command_args.includes?("--headless"))
            socket_path = IPC::SocketPath.resolve(config.server.socket_path)
            logger = Runtime::Logger.new(log_level)
            return Server::Server.new(config, options.config_path, server_options, socket_path, logger).run
          end

          if command == "service"
            action = command_args[0]? || raise Domain::CommandParseError.new("missing service action")
            if command_args.size > 1
              raise Domain::CommandParseError.new("wrong argument count for service")
            end
            stdout.puts (service_installer || Service::ServiceInstaller.new).run(action)
            return 0
          end

          if command.nil?
            palette_line = "/status"
            parsed = Domain::CommandParser.new.parse(palette_line)
            client_commands = ClientCommands.new(IPC::UnixClient.new(client_socket_path(options.config_path)))
            result = client_commands.execute(parsed)
            stdout.puts result.message
            return result.ok ? 0 : 1
          end

          palette_line = cli_to_palette(command, command_args)
          parsed = Domain::CommandParser.new.parse(palette_line)
          client_commands = ClientCommands.new(IPC::UnixClient.new(client_socket_path(options.config_path)))
          if json_output
            response = client_commands.request(parsed)
            exit_code = response.ok ? Domain::ExitCode::Success.value : ClientCommands.exit_code_for(response.error.not_nil!).value
            stdout.puts json_envelope(response.ok, response.result, response.error, exit_code)
            exit_code
          else
            result = client_commands.execute(parsed)
            stdout.puts result.message
            result.ok ? 0 : 1
          end
        rescue ex : Domain::ServerUnavailable
          if json_output
            write_json_error(stdout, IPC::ErrorPayload.from_exception(ex), ex.exit_code.value)
          else
            stderr.puts server_unavailable_message
          end
          ex.exit_code.value
        rescue ex : OptionParser::Exception
          error = Domain::CommandParseError.new(ex.message || "invalid option")
          if json_output
            write_json_error(stdout, IPC::ErrorPayload.from_exception(error), error.exit_code.value)
          else
            stderr.puts error.message
          end
          error.exit_code.value
        rescue ex : Domain::ObsctlError
          if json_output
            write_json_error(stdout, IPC::ErrorPayload.from_exception(ex), ex.exit_code.value)
          else
            stderr.puts ex.message
          end
          ex.exit_code.value
        rescue ex
          if json_output
            write_json_error(stdout, IPC::ErrorPayload.server_error, Domain::ExitCode::Failure.value)
          else
            stderr.puts ex.message
          end
          Domain::ExitCode::Failure.value
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
             "dump-config", "reload-config", "validate-config"
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
