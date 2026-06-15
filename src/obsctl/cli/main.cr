require "./options"
require "./command_router"
require "./client_commands"
require "../config/config_loader"
require "../config/config_writer"
require "../config/config_schema"
require "../domain/command_parser"
require "../domain/errors"
require "../server/server"
require "../server/server_options"
require "../tui/app"

module Obsctl
  module CLI
    module Main
      def self.run(argv : Array(String)) : Int32
        options = OptionsParser.new.parse(argv)
        command = options.command

        if command == "init"
          if File.exists?(options.config_path) && !options.force
            raise Domain::ConfigInvalid.new("config already exists: #{options.config_path}; pass --force to overwrite")
          end
          Config::ConfigWriter.new.write_default(options.config_path)
          puts "created config: #{options.config_path}"
          return 0
        end

        if command == "validate-config"
          Config::ConfigLoader.new.load(options.config_path)
          puts "config valid: #{options.config_path}"
          return 0
        end

        if command == "server"
          config = Config::ConfigLoader.new.load(options.config_path)
          server_options = Server::ServerOptions.new(headless: options.args.includes?("--headless"))
          return Server::Server.new(config, options.config_path, server_options).run
        end

        if command.nil? || command == "tui"
          config = load_config_for(command, options.config_path)
          return TUI::App.new(config, options.config_path).run
        end

        palette_line = cli_to_palette(command, options.args)
        parsed = Domain::CommandParser.new.parse(palette_line)
        result = ClientCommands.new.execute(parsed)
        puts result.message
        result.ok ? 0 : 1
      rescue ex : Domain::ServerUnavailable
        STDERR.puts server_unavailable_message
        ex.exit_code.value
      rescue ex : Domain::ObsctlError
        STDERR.puts ex.message
        ex.exit_code.value
      rescue ex
        STDERR.puts ex.message
        Domain::ExitCode::Failure.value
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

      private def self.load_config_for(command : String?, path : String) : Config::Config
        if command == "dump-config" && !File.exists?(path)
          return Config::Config.default
        end

        if (command.nil? || command == "tui") && !File.exists?(path)
          Config::ConfigWriter.new.write_default(path)
          STDERR.puts "created default config: #{path}"
        end

        Config::ConfigLoader.new.load(path)
      end

      private def self.server_unavailable_message : String
        "obsctl server is not running.\n" \
        "Start it with:\n" \
        "  obsctl server --headless\n" \
        "Or install service:\n" \
        "  obsctl service install\n" \
        "  systemctl --user enable --now obsctl.service"
      end
    end
  end
end
