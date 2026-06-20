require "option_parser"
require "../config/config_paths"

module Obsctl
  module CLI
    record Options,
      config_path : String,
      log_level : String = "info",
      force : Bool = false,
      json : Bool = false,
      command : String? = nil,
      args : Array(String) = [] of String

    class OptionsParser
      def parse(argv : Array(String)) : Options
        config_path = Config::ConfigPaths.default_path
        log_level = "info"
        force = false
        json = false
        command = nil.as(String?)
        args = [] of String
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: obsctl [--config PATH] [--json] [command] [args]"
          opts.on("--config PATH", "Path to config.yml") { |path| config_path = path }
          opts.on("--log-level LEVEL", "debug|info|warn|error") { |level| log_level = level }
          opts.on("--force", "Overwrite files for commands that support it") { force = true }
          opts.on("--json", "Emit a JSON envelope for thin client commands") { json = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end

        index = 0
        while index < argv.size
          arg = argv[index]
          if arg.starts_with?("-")
            option_args = [arg]
            if requires_value?(arg)
              index += 1
              option_args << (argv[index]? || "")
            end
            parser.parse(option_args)
          else
            command = arg
            args = argv[(index + 1)..]? || [] of String
            break
          end
          index += 1
        end

        Options.new(
          config_path: config_path,
          log_level: log_level,
          force: force,
          json: json,
          command: command,
          args: args
        )
      end

      private def requires_value?(arg : String) : Bool
        arg == "--config" || arg == "--log-level"
      end
    end
  end
end
