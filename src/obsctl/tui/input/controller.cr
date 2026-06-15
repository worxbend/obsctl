require "./command_mode"
require "./keymap"

module Obsctl
  module TUI
    module Input
      # High-level action emitted by the keyboard controller.
      enum ActionKind
        None
        Render
        Submit
        Quit
      end

      # Result of handling one input key.
      record Action, kind : ActionKind, command : String? = nil do
        # No UI update or command is needed.
        def self.none : self
          new(ActionKind::None)
        end

        # The current model should be rendered again.
        def self.render : self
          new(ActionKind::Render)
        end

        # The supplied command line should be executed.
        def self.submit(command : String) : self
          new(ActionKind::Submit, command)
        end

        # The TUI should exit.
        def self.quit : self
          new(ActionKind::Quit)
        end
      end

      # Converts raw key input into command palette edits or dashboard actions.
      class Controller
        getter command_mode

        ENTER     = "\r"
        NEWLINE   = "\n"
        BACKSPACE = "\u007f"
        CTRL_H    = "\b"
        ESCAPE    = "\e"
        CTRL_C    = "\u0003"

        def initialize(@keymap : Keymap, @palette_prefix : String = "/")
          @command_mode = CommandMode.new
        end

        # Returns the current command palette line, or an empty string when closed.
        def command_line : String
          @command_mode.active? ? @command_mode.line : ""
        end

        # Handles one key and returns the resulting UI action.
        def handle(key : String) : Action
          return handle_command_key(key) if @command_mode.active?
          return Action.quit if @keymap.quit?(key) || key == CTRL_C

          if @keymap.command_palette?(key)
            @command_mode.open(@palette_prefix)
            return Action.render
          end

          if @keymap.reload_config?(key)
            return Action.submit("/reload-config")
          end

          if @keymap.dump_config?(key)
            return Action.submit("/dump-config")
          end

          Action.none
        end

        private def handle_command_key(key : String) : Action
          case key
          when ENTER, NEWLINE
            if command = @command_mode.submit
              Action.submit(command)
            else
              Action.render
            end
          when BACKSPACE, CTRL_H
            @command_mode.backspace
            Action.render
          when ESCAPE, CTRL_C
            @command_mode.clear
            Action.render
          else
            append_printable(key)
            Action.render
          end
        end

        private def append_printable(key : String) : Nil
          return unless key.size == 1

          char = key[0]
          return if char.control?

          @command_mode.append(char)
        end
      end
    end
  end
end
