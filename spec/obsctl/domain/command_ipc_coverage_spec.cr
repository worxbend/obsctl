require "../../spec_helper"
require "../../../src/obsctl/domain/command"
require "../../../src/obsctl/ipc/command_name"
require "../../../src/obsctl/server/command_executor"

# The client surfaces and the daemon have to agree on the command vocabulary,
# and until these checks existed nothing made them. The CLI would happily put a
# name on the wire that no handler answered, and the failure surfaced as
# `unsupported IPC command` for whoever ran it first rather than for whoever
# wrote it.
describe "IPC command coverage" do
  it "answers every command the client surfaces can send" do
    # `Domain::Command#ipc_name` is what `ClientCommands` and the TUI dispatcher
    # put on the wire, so every non-nil one must have a handler. Commands that
    # resolve entirely client-side (help, quit, connect) return nil and are
    # deliberately absent.
    missing = [] of String
    {% for command in Obsctl::Domain::Command.all_subclasses %}
      {% unless command.abstract? %}
        if name = {{ command }}.allocate.ipc_name
          missing << "{{ command }} -> #{name}" unless Obsctl::Server::CommandExecutor::HANDLERS.has_key?(name)
        end
      {% end %}
    {% end %}

    missing.should be_empty
  end

  it "has a handler for every declared command name" do
    # The other direction: a constant added to `IPC::CommandName` with no
    # handler behind it is a half-finished command, and this is what says so.
    declared = [] of String
    {% for constant in Obsctl::IPC::CommandName.constants %}
      declared << Obsctl::IPC::CommandName::{{ constant }}
    {% end %}

    declared.reject { |name| Obsctl::Server::CommandExecutor::HANDLERS.has_key?(name) }.should be_empty
  end

  it "declares every name it handles" do
    declared = [] of String
    {% for constant in Obsctl::IPC::CommandName.constants %}
      declared << Obsctl::IPC::CommandName::{{ constant }}
    {% end %}

    Obsctl::Server::CommandExecutor::HANDLERS.keys.reject { |name| declared.includes?(name) }.should be_empty
  end
end
