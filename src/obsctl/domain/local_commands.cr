module Obsctl
  module Domain
    # The commands the CLI answers itself instead of sending to the daemon.
    #
    # `CommandRegistry` is the single source of truth for everything that
    # crosses the IPC socket. These do not cross it — `init` writes a file,
    # `doctor` runs diagnostics, `completions` prints a script — so they are
    # declared here instead, but for the same reason and in the same shape.
    #
    # They used to be declared five separate times: the `case` in `CLI::Main`
    # that routes them, `Main::LOCAL_COMMANDS` for `--help`,
    # `Main::LOCAL_JSON_COMMANDS` for the `--json` allowlist,
    # `Main::CONFIG_ACTIONS`, and `Completions::LOCAL_COMMANDS` for the shell
    # scripts. Nothing kept those five in step, so a command could be
    # completable but undocumented, or documented but refuse `--json`.
    # `spec/obsctl/domain/local_commands_spec.cr` checks this list against the
    # routing that consumes it.
    struct LocalCommandSpec
      getter name : String
      getter summary : String
      # Argument spelling shown in `--help`, e.g. `explain|diff|migrate`.
      getter usage_arguments : String
      # Fixed subcommands, offered by shell completion. Empty when the command
      # takes none.
      getter subcommands : Array(String)
      getter? json : Bool

      def initialize(
        @name : String,
        @summary : String,
        @usage_arguments : String = "",
        @subcommands : Array(String) = [] of String,
        @json : Bool = false,
      )
      end

      # `name args` as shown in help.
      def usage : String
        @usage_arguments.empty? ? @name : "#{@name} #{@usage_arguments}"
      end
    end

    module LocalCommands
      extend self

      SPECS = [
        LocalCommandSpec.new(
          name: "init", summary: "Write a default config file"),
        LocalCommandSpec.new(
          name: "doctor", summary: "Run setup diagnostics", json: true),
        LocalCommandSpec.new(
          name: "config", summary: "Inspect or migrate the config file",
          usage_arguments: "explain|diff|migrate",
          subcommands: ["explain", "diff", "migrate"], json: true),
        LocalCommandSpec.new(
          name: "watch", summary: "Stream daemon events as newline-delimited JSON",
          usage_arguments: "[--topics LIST]", json: true),
        LocalCommandSpec.new(
          name: "completions", summary: "Print a shell completion script",
          usage_arguments: "bash|zsh|fish",
          subcommands: ["bash", "zsh", "fish"]),
        LocalCommandSpec.new(
          name: "server", summary: "Run the local daemon in the foreground",
          usage_arguments: "[--headless]"),
        LocalCommandSpec.new(
          name: "service", summary: "Manage the systemd --user unit",
          usage_arguments: "install|start|stop|restart|status|uninstall",
          subcommands: ["install", "uninstall", "start", "stop", "restart", "status"]),
        LocalCommandSpec.new(
          name: "tui", summary: "Open the dashboard (the default with no command)"),
        LocalCommandSpec.new(
          name: "version", summary: "Show the obsctl version"),
      ]

      # `validate-config` is deliberately absent from `SPECS`: it is a daemon
      # command in `CommandRegistry` that the CLI *also* answers locally, so
      # listing it here would document and complete it twice.
      LOCALLY_ANSWERED_DAEMON_COMMANDS = ["validate-config"]

      def []?(name : String) : LocalCommandSpec?
        SPECS.find { |spec| spec.name == name }
      end

      def names : Array(String)
        SPECS.map(&.name)
      end

      # Every word the shell should offer in the command position, including
      # `help`, which `OptionParser` answers rather than `dispatch`.
      def completion_names : Array(String)
        names + ["help"]
      end

      # The fixed subcommands one command takes, or an empty list.
      def subcommands_for(name : String) : Array(String)
        self[name]?.try(&.subcommands) || [] of String
      end

      # Fixed subcommands, keyed by the command that takes them.
      def subcommands : Hash(String, Array(String))
        table = {} of String => Array(String)
        SPECS.each { |spec| table[spec.name] = spec.subcommands unless spec.subcommands.empty? }
        table
      end

      # True when this command can render a `--json` envelope.
      def json?(name : String) : Bool
        self[name]?.try(&.json?) || LOCALLY_ANSWERED_DAEMON_COMMANDS.includes?(name)
      end

      # One line per command, aligned on the usage column.
      def help_lines : Array(String)
        usages = SPECS.map(&.usage)
        width = usages.max_of?(&.size) || 0
        SPECS.zip(usages).map { |spec, usage| "#{usage.ljust(width)}  #{spec.summary}" }
      end
    end
  end
end
