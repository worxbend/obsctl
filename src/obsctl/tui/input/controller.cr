require "./command_mode"
require "./keymap"

module Obsctl
  module TUI
    module Input
      enum ActionKind
        None
        Render
        Submit
        Quit
      end

      record Action, kind : ActionKind, command : String? = nil do
        def self.none : self
          new(ActionKind::None)
        end

        def self.render : self
          new(ActionKind::Render)
        end

        def self.submit(command : String) : self
          new(ActionKind::Submit, command)
        end

        def self.quit : self
          new(ActionKind::Quit)
        end
      end

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

        def command_line : String
          @command_mode.active? ? @command_mode.line : ""
        end

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
