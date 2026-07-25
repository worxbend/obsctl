require "option_parser"
require "../config/config_paths"
require "../domain/errors"
require "./color"

module Obsctl
  module CLI
    record Options,
      config_path : String,
      log_level : String = "info",
      force : Bool = false,
      json : Bool = false,
      version : Bool = false,
      quiet : Bool = false,
      color : ColorMode = ColorMode::Auto,
      timeout : Time::Span? = nil,
      help : Bool = false,
      help_text : String = "",
      command : String? = nil,
      args : Array(String) = [] of String

    # One global option, declared once.
    #
    # The argv splitter has to know whether a flag consumes the following token
    # before `OptionParser` ever sees it, because everything from the first
    # positional onwards belongs to the subcommand and may contain flags this
    # parser knows nothing about (`--topics`, `--headless`, `--dry-run`).
    # Declaring the flags as data keeps the splitter and the parser from
    # disagreeing about where the global section ends.
    record FlagSpec, long : String, value : String? = nil, short : String? = nil, description : String = "" do
      # Renders the flag in the form `OptionParser#on` expects.
      def to_flag : String
        value ? "#{long} #{value}" : long
      end

      # True when this flag takes a separate following token.
      def takes_value? : Bool
        !value.nil?
      end
    end

    class OptionsParser
      BANNER = "Usage: obsctl [global options] [command] [args]"

      FLAGS = [
        FlagSpec.new("--config", "PATH", description: "Path to config.yml"),
        FlagSpec.new("--log-level", "LEVEL", description: "debug|info|warn|error"),
        FlagSpec.new("--color", "WHEN", description: "auto|always|never (default: auto)"),
        FlagSpec.new("--timeout", "SECONDS", description: "Give up on a daemon request after SECONDS"),
        FlagSpec.new("--force", description: "Overwrite files for commands that support it"),
        FlagSpec.new("--json", description: "Emit a JSON envelope for scriptable commands"),
        FlagSpec.new("--quiet", short: "-q", description: "Suppress human output; rely on the exit code"),
        FlagSpec.new("--version", short: "-V", description: "Show the obsctl version"),
        FlagSpec.new("--help", short: "-h", description: "Show help"),
      ]

      def parse(argv : Array(String)) : Options
        config_path = Config::ConfigPaths.default_path
        log_level = "info"
        force = false
        json = false
        version = false
        quiet = false
        help = false
        color = ColorMode::Auto
        timeout = nil.as(Time::Span?)

        parser = OptionParser.new do |opts|
          opts.banner = BANNER
          FLAGS.each do |flag|
            handler = ->(value : String) do
              case flag.long
              when "--config"    then config_path = value
              when "--log-level" then log_level = value
              when "--color"     then color = ColorMode.from_option(value)
              when "--timeout"   then timeout = parse_timeout(value)
              when "--force"     then force = true
              when "--json"      then json = true
              when "--quiet"     then quiet = true
              when "--version"   then version = true
              when "--help"      then help = true
              end
              nil
            end

            if short = flag.short
              opts.on(short, flag.to_flag, flag.description) { |value| handler.call(value) }
            else
              opts.on(flag.to_flag, flag.description) { |value| handler.call(value) }
            end
          end
        end

        global_argv, command, args = split(argv)
        parser.parse(global_argv)

        Options.new(
          config_path: config_path,
          log_level: log_level,
          force: force,
          json: json,
          version: version,
          quiet: quiet,
          color: color,
          timeout: timeout,
          help: help,
          help_text: parser.to_s,
          command: command,
          args: args
        )
      end

      # Splits argv into the global option section, the command, and its args.
      private def split(argv : Array(String)) : Tuple(Array(String), String?, Array(String))
        index = 0
        while index < argv.size
          arg = argv[index]
          break unless arg.starts_with?('-')

          index += 1
          index += 1 if takes_separate_value?(arg) && index < argv.size
        end

        global_argv = argv[0...index]
        command = argv[index]?
        args = command ? argv[(index + 1)..] : [] of String
        {global_argv, command, args}
      end

      # `--flag=value` carries its own value, so only the bare spelling of a
      # value-taking flag consumes the next token.
      private def takes_separate_value?(arg : String) : Bool
        return false if arg.includes?('=')

        FLAGS.any? do |flag|
          flag.takes_value? && (arg == flag.long || arg == flag.short)
        end
      end

      private def parse_timeout(value : String) : Time::Span
        seconds = value.to_f?
        unless seconds && seconds > 0
          raise Domain::CommandParseError.new("--timeout must be a positive number of seconds")
        end

        seconds.seconds
      end
    end
  end
end
