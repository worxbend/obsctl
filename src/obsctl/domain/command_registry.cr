require "./command"
require "./errors"

module Obsctl
  module Domain
    # What a command's argument names, used to drive completion.
    enum ArgumentKind
      None
      Scene
      Profile
      SceneCollection
      AudioInput
      Percent
      RecordAction

      # Human placeholder shown in help and usage errors.
      #
      # The record actions are read off the parser's own action table, so an
      # action added there cannot go unadvertised in `--help` and the generated
      # shell completions.
      def placeholder : String
        case self
        in None            then ""
        in Scene           then "<scene>"
        in Profile         then "<profile>"
        in SceneCollection then "<collection>"
        in AudioInput      then "<audio-input>"
        in Percent         then "<0-100>"
        in RecordAction    then "[#{CommandRegistry::RECORD_ACTIONS.keys.join('|')}]"
        end
      end
    end

    # Where a command is offered.
    @[Flags]
    enum CommandSurface
      Cli
      Palette
    end

    # One command, declared once.
    #
    # This is the single source of truth for the command set. The parser, the
    # `--json` allowlist, palette completion, `--help`, and the generated shell
    # completions all read it, so a command cannot exist on one surface and be
    # missing from another.
    struct CommandSpec
      getter name : String
      getter aliases : Array(String)
      getter arguments : Array(ArgumentKind)
      getter required_arguments : Int32
      getter summary : String
      getter surface : CommandSurface
      getter? json : Bool
      getter build : Proc(Array(String), Command)

      def initialize(
        @name : String,
        @summary : String,
        @build : Proc(Array(String), Command),
        @aliases : Array(String) = [] of String,
        @arguments : Array(ArgumentKind) = [] of ArgumentKind,
        @required_arguments : Int32 = -1,
        @surface : CommandSurface = CommandSurface::Cli | CommandSurface::Palette,
        @json : Bool = false,
      )
        @required_arguments = @arguments.size if @required_arguments < 0
      end

      # Every spelling that resolves to this command.
      def spellings : Array(String)
        [@name] + @aliases
      end

      def cli? : Bool
        @surface.cli?
      end

      def palette? : Bool
        @surface.palette?
      end

      # `name <arg> <arg>` as shown in help.
      def usage : String
        ([@name] + @arguments.map(&.placeholder)).join(' ').rstrip
      end

      # Validates the supplied argument count against this command's arity.
      def validate_arity!(args : Array(String)) : Nil
        return if @required_arguments <= args.size <= @arguments.size

        raise CommandParseError.new("wrong argument count for #{@name}; usage: #{usage}")
      end
    end

    # The command set, and lookups over it.
    module CommandRegistry
      extend self

      # Record subcommands. Bare `rec` keeps its original toggle behavior.
      RECORD_ACTIONS = {
        "start"  => -> { StartRecordCommand.new.as(Command) },
        "stop"   => -> { StopRecordCommand.new.as(Command) },
        "toggle" => -> { ToggleRecordCommand.new.as(Command) },
        "pause"  => -> { PauseRecordCommand.new.as(Command) },
        "resume" => -> { ResumeRecordCommand.new.as(Command) },
        "status" => -> { RecordStatusCommand.new.as(Command) },
      }

      SPECS = [
        CommandSpec.new(
          name: "help", summary: "List available commands",
          surface: CommandSurface::Palette,
          build: ->(_args : Array(String)) { HelpCommand.new.as(Command) }),
        CommandSpec.new(
          name: "quit", aliases: ["exit"], summary: "Leave the dashboard",
          surface: CommandSurface::Palette,
          build: ->(_args : Array(String)) { QuitCommand.new.as(Command) }),
        CommandSpec.new(
          name: "connect", summary: "Ask the session to connect",
          surface: CommandSurface::Palette,
          build: ->(_args : Array(String)) { ConnectCommand.new.as(Command) }),
        CommandSpec.new(
          name: "disconnect", summary: "Ask the session to disconnect",
          surface: CommandSurface::Palette,
          build: ->(_args : Array(String)) { DisconnectCommand.new.as(Command) }),

        CommandSpec.new(
          name: "status", summary: "Show combined daemon and OBS status", json: true,
          build: ->(_args : Array(String)) { StatusCommand.new.as(Command) }),
        CommandSpec.new(
          name: "server-status", summary: "Show local daemon status only", json: true,
          build: ->(_args : Array(String)) { ServerStatusCommand.new.as(Command) }),
        CommandSpec.new(
          name: "obs-status", summary: "Show OBS connection and state", json: true,
          build: ->(_args : Array(String)) { ObsStatusCommand.new.as(Command) }),
        CommandSpec.new(
          name: "reconnect", summary: "Ask the daemon to reconnect to OBS", json: true,
          build: ->(_args : Array(String)) { ReconnectCommand.new.as(Command) }),
        CommandSpec.new(
          name: "shutdown-server", summary: "Ask the daemon to shut down", json: true,
          build: ->(_args : Array(String)) { ShutdownServerCommand.new.as(Command) }),

        CommandSpec.new(
          name: "scene", aliases: ["set-scene"], summary: "Switch the current program scene",
          arguments: [ArgumentKind::Scene], json: true,
          build: ->(args : Array(String)) { SetSceneCommand.new(args[0]).as(Command) }),
        CommandSpec.new(
          name: "profile", aliases: ["set-profile"], summary: "Switch the active profile",
          arguments: [ArgumentKind::Profile], json: true,
          build: ->(args : Array(String)) { SetProfileCommand.new(args[0]).as(Command) }),
        CommandSpec.new(
          name: "collection", aliases: ["set-collection", "scene-collection"],
          summary: "Switch the active scene collection",
          arguments: [ArgumentKind::SceneCollection], json: true,
          build: ->(args : Array(String)) { SetSceneCollectionCommand.new(args[0]).as(Command) }),

        CommandSpec.new(
          name: "mute", summary: "Mute an audio input",
          arguments: [ArgumentKind::AudioInput], json: true,
          build: ->(args : Array(String)) { MuteCommand.new(args[0]).as(Command) }),
        CommandSpec.new(
          name: "unmute", summary: "Unmute an audio input",
          arguments: [ArgumentKind::AudioInput], json: true,
          build: ->(args : Array(String)) { UnmuteCommand.new(args[0]).as(Command) }),
        CommandSpec.new(
          name: "toggle-mute", summary: "Toggle mute for an audio input",
          arguments: [ArgumentKind::AudioInput], json: true,
          build: ->(args : Array(String)) { ToggleMuteCommand.new(args[0]).as(Command) }),
        CommandSpec.new(
          name: "vol", aliases: ["volume"], summary: "Set an audio input's volume percentage",
          arguments: [ArgumentKind::AudioInput, ArgumentKind::Percent], json: true,
          build: ->(args : Array(String)) { VolumeCommand.new(args[0], CommandRegistry.parse_percent(args[1])).as(Command) }),

        CommandSpec.new(
          name: "stream", summary: "Toggle streaming", json: true,
          build: ->(_args : Array(String)) { ToggleStreamCommand.new.as(Command) }),
        CommandSpec.new(
          name: "rec", aliases: ["record"], summary: "Control the recording output",
          arguments: [ArgumentKind::RecordAction], required_arguments: 0, json: true,
          build: ->(args : Array(String)) { CommandRegistry.build_record(args) }),

        CommandSpec.new(
          name: "dump-config", summary: "Merge live OBS names into the config file", json: true,
          build: ->(_args : Array(String)) { DumpConfigCommand.new.as(Command) }),
        CommandSpec.new(
          name: "reload-config", summary: "Reload the daemon's config from disk", json: true,
          build: ->(_args : Array(String)) { ReloadConfigCommand.new.as(Command) }),
        CommandSpec.new(
          name: "validate-config", summary: "Validate the config file", json: true,
          build: ->(_args : Array(String)) { ValidateConfigCommand.new.as(Command) }),
      ]

      # Every spelling mapped to its spec, including aliases.
      BY_NAME = begin
        table = {} of String => CommandSpec
        SPECS.each do |spec|
          spec.spellings.each { |spelling| table[spelling] = spec }
        end
        table
      end

      # Resolves one spelling, case-insensitively and with any leading slash.
      def []?(name : String) : CommandSpec?
        BY_NAME[normalize(name)]?
      end

      # Strips the palette prefix so `/scene` and `scene` resolve alike.
      def normalize(name : String) : String
        name.lstrip('/').downcase
      end

      # Specs offered on the given surface, in declaration order.
      def for_surface(surface : CommandSurface) : Array(CommandSpec)
        SPECS.select(&.surface.includes?(surface))
      end

      # True when the CLI can render this command as a JSON envelope.
      def json?(name : String?) : Bool
        return false unless name

        self[name]?.try(&.json?) || false
      end

      # Canonical palette names, slash-prefixed, for completion.
      #
      # Aliases stay parseable but are left out of suggestions: offering both
      # `/collection` and `/scene-collection` for `/sc` is noise, not help.
      def palette_names : Array(String)
        for_surface(CommandSurface::Palette).map { |spec| "/#{spec.name}" }
      end

      # Canonical CLI names, for shell completion and usage errors.
      def cli_names : Array(String)
        for_surface(CommandSurface::Cli).map(&.name)
      end

      # Every accepted CLI spelling, aliases included.
      def cli_spellings : Array(String)
        for_surface(CommandSurface::Cli).flat_map(&.spellings)
      end

      # One-line-per-command help, aligned on the usage column.
      def help_lines(surface : CommandSurface, prefix : String = "") : Array(String)
        specs = for_surface(surface)
        usages = specs.map { |spec| "#{prefix}#{spec.usage}" }
        width = usages.max_of?(&.size) || 0
        specs.zip(usages).map { |spec, usage| "#{usage.ljust(width)}  #{spec.summary}" }
      end

      def build_record(args : Array(String)) : Command
        return ToggleRecordCommand.new if args.empty?

        action = args[0].downcase
        build = RECORD_ACTIONS[action]?
        unless build
          raise CommandParseError.new("unknown record action: #{args[0]}; expected #{RECORD_ACTIONS.keys.join(", ")}")
        end

        build.call
      end

      def parse_percent(value : String) : Int32
        percent = value.to_i?
        raise CommandParseError.new("volume must be an integer from 0 to 100") unless percent
        raise CommandParseError.new("volume must be from 0 to 100") unless 0 <= percent <= 100

        percent
      end
    end
  end
end
