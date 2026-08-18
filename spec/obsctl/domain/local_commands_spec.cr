require "../../spec_helper"
require "../../../src/obsctl/cli/completions"
require "../../../src/obsctl/domain/local_commands"

# `Domain::LocalCommands` declares the locally-answered command surface, and
# three consumers read it: the routing `case` in `CLI::Main.dispatch`, `--help`,
# and the generated shell completions. The declaration and the routing are the
# two halves that can drift — a command can be declared and never routed, which
# documents and completes something that then reports "unknown command".
private def routed_command_names : Array(String)
  source = File.read(File.expand_path("../../../src/obsctl/cli/main.cr", __DIR__))
  body = source[/case command\n.*?\n        end/m]? || raise "could not locate the dispatch case"
  body.scan(/"([a-z-]+)"/).map(&.[1]).uniq!
end

describe Obsctl::Domain::LocalCommands do
  it "routes every command it declares" do
    # `tui` is reached through the `when nil, "tui"` arm, and `version` and
    # `help` are answered before the case is entered at all, so all three are
    # routed without appearing as an ordinary arm.
    answered_before_dispatch = ["version"]
    undeclared = Obsctl::Domain::LocalCommands.names -
                 routed_command_names -
                 answered_before_dispatch

    undeclared.should be_empty
  end

  it "declares every command the dispatch case routes" do
    # The other direction: an arm added to the case without a declaration is a
    # command that works but is invisible to `--help` and to the shell.
    daemon_commands = Obsctl::Domain::CommandRegistry.cli_spellings
    unrouted = routed_command_names -
               Obsctl::Domain::LocalCommands.names -
               daemon_commands

    unrouted.should be_empty
  end

  it "offers every declared command to the shell" do
    offered = Obsctl::CLI::Completions.commands
    Obsctl::Domain::LocalCommands.names.reject { |name| offered.includes?(name) }.should be_empty
  end

  it "documents every declared command in --help" do
    help = Obsctl::Domain::LocalCommands.help_lines
    Obsctl::Domain::LocalCommands.names.each do |name|
      help.any?(&.starts_with?(name)).should be_true
    end
  end

  it "accepts --json only for commands that can render an envelope" do
    # `init`, `server`, `tui`, `service`, and `completions` have no envelope to
    # render, and claiming otherwise would make `--json` print nothing useful
    # while still exiting 0.
    Obsctl::Domain::LocalCommands.json?("doctor").should be_true
    Obsctl::Domain::LocalCommands.json?("config").should be_true
    Obsctl::Domain::LocalCommands.json?("watch").should be_true
    Obsctl::Domain::LocalCommands.json?("validate-config").should be_true

    Obsctl::Domain::LocalCommands.json?("init").should be_false
    Obsctl::Domain::LocalCommands.json?("server").should be_false
    Obsctl::Domain::LocalCommands.json?("tui").should be_false
  end
end
