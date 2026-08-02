require "../../crytui"
require "./action"

module Obsctl
  module TUI
    # The multi-key half of the dashboard keymap, in the shape an AstroNvim user
    # already has in their fingers: a leader key that opens a which-key menu,
    # `g` for goto motions, and `Ctrl-w` for window moves.
    #
    # Single-key bindings stay in `Input` because they resolve without any
    # pending state. Everything here is a sequence, so it lives in one table
    # that both the resolver and the which-key panel read — a binding cannot be
    # dispatchable but missing from the menu, or listed but unbound.
    module Keymap
      # Space, the AstroNvim leader. Written as a token so sequences read the
      # way they do in a Neovim config rather than starting with a space.
      LEADER = "<leader>"

      record Binding, sequence : String, kind : ActionKind, description : String

      # A key that can be pressed next, given what has been pressed so far.
      record Entry, token : String, label : String, sequence : String, group : Bool

      BINDINGS = [
        Binding.new("gg", ActionKind::NavigateTop, "first item"),
        Binding.new("G", ActionKind::NavigateBottom, "last item"),
        Binding.new("<C-d>", ActionKind::NavigateHalfPageDown, "half page down"),
        Binding.new("<C-u>", ActionKind::NavigateHalfPageUp, "half page up"),
        Binding.new("<C-w>h", ActionKind::FocusPaneLeft, "pane left"),
        Binding.new("<C-w>j", ActionKind::FocusPaneDown, "pane down"),
        Binding.new("<C-w>k", ActionKind::FocusPaneUp, "pane up"),
        Binding.new("<C-w>l", ActionKind::FocusPaneRight, "pane right"),
        Binding.new("#{LEADER}q", ActionKind::Quit, "quit"),
        Binding.new("#{LEADER}m", ActionKind::ToggleMute, "toggle mute"),
        Binding.new("#{LEADER}fs", ActionKind::FocusScenes, "scenes"),
        Binding.new("#{LEADER}fa", ActionKind::FocusAudio, "audio"),
        Binding.new("#{LEADER}fp", ActionKind::FocusProfiles, "profiles"),
        Binding.new("#{LEADER}fc", ActionKind::FocusCollections, "collections"),
        Binding.new("#{LEADER}ut", ActionKind::OpenSettings, "themes"),
        Binding.new("#{LEADER}or", ActionKind::ReloadConfig, "reload config"),
        Binding.new("#{LEADER}od", ActionKind::DumpConfig, "dump config"),
        Binding.new("#{LEADER}oc", ActionKind::RetryConnect, "reconnect"),
      ]

      # Titles for the prefixes that are groups rather than commands.
      GROUPS = {
        LEADER       => "obsctl",
        "#{LEADER}f" => "find",
        "#{LEADER}u" => "ui",
        "#{LEADER}o" => "obs",
        "g"          => "goto",
        "<C-w>"      => "window",
      }

      extend self

      # The action a completed sequence runs, or nil when it is not a binding.
      def [](sequence : String) : ActionKind?
        BINDINGS.find { |binding| binding.sequence == sequence }.try(&.kind)
      end

      # True when at least one binding continues past `sequence`, which is what
      # makes a key worth holding onto instead of discarding.
      def prefix?(sequence : String) : Bool
        BINDINGS.any? { |binding| binding.sequence.starts_with?(sequence) && binding.sequence != sequence }
      end

      # The key token for a press, or nil for keys that never start a sequence.
      def token(key : CryTUI::KeyEvent) : String?
        character = key.character
        return unless character && key.code.character?
        return "<C-#{character.downcase}>" if key.modifiers.control?
        return LEADER if character == ' '
        character.to_s
      end

      # Every key that can follow `pending`, for the which-key panel and for
      # clicks on it. Sorted so the menu order is stable between frames.
      def continuations(pending : String) : Array(Entry)
        prefix = tokens(pending)
        depth = prefix.size
        seen = Set(String).new
        entries = [] of Entry
        BINDINGS.each do |binding|
          parts = tokens(binding.sequence)
          next unless parts.size > depth && parts.first(depth) == prefix
          token = parts[depth]
          next unless seen.add?(token)

          sequence = pending + token
          group = parts.size > depth + 1
          entries << Entry.new(token, group ? (GROUPS[sequence]? || "more") : binding.description, sequence, group)
        end
        entries.sort_by!(&.token.downcase)
      end

      # What the which-key panel calls the sequence being typed.
      def title(pending : String) : String
        group = GROUPS[pending]?
        group ? "#{pending}  #{group}" : pending
      end

      # Splits a sequence into keys, keeping `<...>` tokens whole.
      def tokens(sequence : String) : Array(String)
        result = [] of String
        index = 0
        while index < sequence.size
          if sequence[index] == '<' && (close = sequence.index('>', index))
            result << sequence[index..close]
            index = close + 1
          else
            result << sequence[index].to_s
            index += 1
          end
        end
        result
      end
    end
  end
end
