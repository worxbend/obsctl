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
    # The completion-facing fields exist so the generated shell scripts read
    # off this table too instead of re-listing every flag per shell:
    # `candidates` is the fixed word list a value flag accepts,
    # `file_completion` marks a value flag whose value is a path, and
    # `value_label` is the short lowercase noun zsh shows for the value
    # (`--help` keeps the uppercase placeholder in `value`).
    record FlagSpec,
      long : String,
      value : String? = nil,
      short : String? = nil,
      description : String = "",
      shell_description : String? = nil,
      candidates : Array(String)? = nil,
      value_label : String? = nil,
      file_completion : Bool = false do
      # Renders the flag in the form `OptionParser#on` expects.
      def to_flag : String
        value ? "#{long} #{value}" : long
      end

      # True when this flag takes a separate following token.
      def takes_value? : Bool
        !value.nil?
      end

      # What the shell completion shows for this flag. `--help` descriptions
      # like "debug|info|warn|error" restate the value list, which the shells
      # already render as candidates, so a flag may carry a shorter
      # completion-only wording and falls back to `description` otherwise.
      def completion_description : String
        shell_description || description
      end
    end

    class OptionsParser
      BANNER = "Usage: obsctl [global options] [command] [args]"

      FLAGS = [
        FlagSpec.new("--config", "PATH", description: "Path to config.yml",
          value_label: "file", file_completion: true),
        FlagSpec.new("--log-level", "LEVEL", description: "debug|info|warn|error",
          shell_description: "Log verbosity", candidates: ["debug", "info", "warn", "error"], value_label: "level"),
        FlagSpec.new("--color", "WHEN", description: "auto|always|never (default: auto)",
          shell_description: "When to colorize", candidates: ["auto", "always", "never"], value_label: "when"),
        FlagSpec.new("--timeout", "SECONDS", description: "Give up on a daemon request after SECONDS",
          shell_description: "Request timeout in seconds", value_label: "seconds"),
        FlagSpec.new("--force", description: "Overwrite files for commands that support it",
          shell_description: "Overwrite files"),
        FlagSpec.new("--json", description: "Emit a JSON envelope for scriptable commands",
          shell_description: "Emit a JSON envelope"),
        FlagSpec.new("--quiet", short: "-q", description: "Suppress human output; rely on the exit code",
          shell_description: "Suppress human output"),
        FlagSpec.new("--version", short: "-V", description: "Show the obsctl version",
          shell_description: "Show the version"),
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
        command, args = translate_scene_profile_flags(command, args)

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
      # Rewrites `obsctl scene-profile --off` and `--delete NAME` into the
      # canonical commands `scene-profile-off` and `scene-profile-delete NAME`
      # before the registry sees them.
      #
      # Done here rather than by teaching `CommandRegistry` about flags: every
      # spec there is a name plus positional arguments, and the registry is what
      # drives `--help`, the `--json` allowlist and the generated shell
      # completions. Translating keeps the flag spellings obsctl-rs offers
      # without putting a second argument grammar into the single source of
      # truth.
      private def translate_scene_profile_flags(command : String?, args : Array(String)) : Tuple(String?, Array(String))
        return {command, args} unless command == "scene-profile" || command == "set-scene-profile"

        case args.first?
        when "--off", "--clear"
          raise Domain::CommandParseError.new("scene-profile #{args.first} takes no argument") if args.size > 1
          {"scene-profile-off", [] of String}
        when "--delete"
          raise Domain::CommandParseError.new("scene-profile --delete needs a scene profile name") unless args.size == 2
          {"scene-profile-delete", [args[1]]}
        else
          {command, args}
        end
      end

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
