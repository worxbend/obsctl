require "option_parser"
require "../config/config_paths"

module Obsctl
  module CLI
    record Options,
      config_path : String,
      log_level : String = "info",
      force : Bool = false,
      command : String? = nil,
      args : Array(String) = [] of String

    class OptionsParser
      def parse(argv : Array(String)) : Options
        config_path = Config::ConfigPaths.default_path
        log_level = "info"
        force = false
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: obsctl [--config PATH] [command] [args]"
          opts.on("--config PATH", "Path to config.yml") { |path| config_path = path }
          opts.on("--log-level LEVEL", "debug|info|warn|error") { |level| log_level = level }
          opts.on("--force", "Overwrite files for commands that support it") { force = true }
          opts.on("-h", "--help", "Show help") do
            puts opts
            exit 0
          end
        end
        remaining = argv.dup
        parser.parse(remaining)
        Options.new(
          config_path: config_path,
          log_level: log_level,
          force: force,
          command: remaining[0]?,
          args: remaining[1..]? || [] of String
        )
      end
    end
  end
end
