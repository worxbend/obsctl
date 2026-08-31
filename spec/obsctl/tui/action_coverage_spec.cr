require "../../spec_helper"
require "../../../src/obsctl/tui/dispatcher"

private DISPATCHER_PATH = File.expand_path("../../../src/obsctl/tui/dispatcher.cr", __DIR__)

# Every arm the dispatcher's `case action.kind` chain tests, read out of the
# source. Crystal's enum predicates (`.open_palette?`) are how those arms are
# written, and an arm may test several in one go -- `when .apply_settings_theme?,
# .pointer_settings_apply?` -- so each line contributes every predicate on it.
# Only the part before `then` is read, so a one-line body cannot be mistaken for
# an arm of its own.
private def dispatched_predicates : Set(String)
  predicates = Set(String).new

  File.read(DISPATCHER_PATH).each_line do |line|
    next unless match = line.match(/^\s*when\s+(.+)$/)

    conditions = match[1].split(" then ").first
    conditions.scan(/\.([a-z0-9_]+)\?/) { |predicate| predicates << predicate[1] }
  end

  predicates
end

describe "TUI action routing" do
  it "routes every action kind somewhere in the dispatcher" do
    # `Dispatcher#dispatch` is a chain of handlers, each answering nil for an
    # action it does not own and the chain ending in `ActionOutcome::HANDLED`.
    # That fallback is what makes an unrouted kind silent: add a member to
    # `ActionKind`, bind a key to it, forget the arm, and the key does nothing
    # at all -- no compile error, no failing example, no message on screen.
    # This is the check that would have caught it.
    routed = dispatched_predicates
    # Three kinds are routed without an arm of their own. The two sequence
    # kinds are answered by `dispatch`'s first line, and the focus moves and
    # pointer kinds are looked up in tables rather than tested one by one.
    routed << Obsctl::TUI::ActionKind::PendingSequence.to_s.underscore
    routed << Obsctl::TUI::ActionKind::ClearSequence.to_s.underscore
    Obsctl::TUI::Dispatcher::FOCUS_ACTIONS.each_key { |kind| routed << kind.to_s.underscore }
    Obsctl::TUI::Dispatcher::POINTER_KINDS.each { |kind| routed << kind.to_s.underscore }

    unrouted = Obsctl::TUI::ActionKind.values.reject { |kind| routed.includes?(kind.to_s.underscore) }

    unrouted.map(&.to_s).should eq([] of String)
  end
end
