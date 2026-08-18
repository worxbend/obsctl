require "../../spec_helper"
require "../../../src/obsctl/cli/client_commands"
require "../../../src/obsctl/domain/errors"
require "../../../src/obsctl/ipc/response"

# An error raised in the daemon reaches the user's shell as an exit code by way
# of two independently maintained tables: `ErrorCode.for_exception` turns the
# exception into a wire code, and `ClientCommands.exit_code_for` turns that wire
# code back into an exit code. Nothing but agreement between those two makes
# `obsctl scene nope; echo $?` print what `docs/commands.md` promises, and until
# this spec existed nothing checked that agreement.
describe "IPC error code round trip" do
  # One instance per concrete error class, built with whatever arguments its
  # constructor needs.
  errors = [
    Obsctl::Domain::ConfigNotFound.new("/tmp/nope.yml"),
    Obsctl::Domain::ConfigInvalid.new("bad"),
    Obsctl::Domain::ConnectionFailed.new("refused"),
    Obsctl::Domain::AuthenticationFailed.new,
    Obsctl::Domain::RequestTimeout.new("GetVersion"),
    Obsctl::Domain::ObsRequestFailed.new("SetCurrentProgramScene", "nope"),
    Obsctl::Domain::ObsUnavailable.new,
    Obsctl::Domain::ServerUnavailable.new,
    Obsctl::Domain::SceneNotFound.new("Main"),
    Obsctl::Domain::AudioInputNotFound.new("Mic"),
    Obsctl::Domain::AliasAmbiguous.new("scene", "Main"),
    Obsctl::Domain::CommandParseError.new("bad"),
    Obsctl::Domain::ShutdownDisabled.new,
    Obsctl::Domain::IpcProtocolError.new("bad frame"),
  ] of Obsctl::Domain::ObsctlError

  # Errors that never make the round trip, and why. Listing them is the point:
  # the coverage check below reads this, so excluding a class is a decision
  # someone wrote down rather than a gap nobody noticed.
  non_transmissible = Set{
    # Raised on both sides of the socket for two different conditions. The
    # client-side raises ("cannot reach the server") are all converted to
    # `ServerUnavailable` before they reach a user — see `ClientCommands#request`,
    # `TUI::Session`, and `Watcher` — so they exit 3 as documented. The
    # server-side raises (`UnixServer#bind`, `SocketPath.assert_safe_parent!`)
    # are genuine IPC-layer faults in the daemon's own setup, exit 6, and have
    # no client to send a response to.
    "Obsctl::Domain::IpcConnectionFailed",
    # Carries an exit code chosen by the caller rather than mapped from a wire
    # code, so it has no fixed round trip.
    "Obsctl::Domain::RemoteCommandFailed",
    # A local systemd operation. It never crosses the IPC boundary.
    "Obsctl::Domain::ServiceInstallFailed",
  }

  errors.each do |error|
    it "preserves #{error.class}'s exit code across the wire" do
      payload = Obsctl::IPC::ErrorPayload.from_exception(error)
      Obsctl::CLI::ClientCommands.exit_code_for(payload).should eq(error.exit_code)
    end
  end

  it "covers every error class that maps to a non-default exit code" do
    # A new error class with its own exit code but no entry in either table
    # would silently exit 1. This lists what the round trip above actually
    # exercised so adding a class without adding a case here is visible.
    covered = errors.map(&.class.name).to_set
    uncovered = [] of String
    {% for subclass in Obsctl::Domain::ObsctlError.all_subclasses %}
      {% unless subclass.abstract? %}
        name = {{ subclass.stringify }}
        uncovered << name unless covered.includes?(name) || non_transmissible.includes?(name)
      {% end %}
    {% end %}

    uncovered.should be_empty
  end
end
