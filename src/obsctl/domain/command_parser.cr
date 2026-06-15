require "./command"
require "./errors"

module Obsctl
  module Domain
    # Parses CLI and TUI command text into typed command objects.
    class CommandParser
      # Parses one command line, including quoted arguments.
      def parse(input : String) : Command
        tokens = tokenize(input.strip)
        raise CommandParseError.new("empty command") if tokens.empty?

        command = tokens[0]
        command = command[1..] if command.starts_with?("/")

        case command
        when "help"
          expect_count(tokens, 1)
          HelpCommand.new
        when "quit", "exit"
          expect_count(tokens, 1)
          QuitCommand.new
        when "dump-config"
          expect_count(tokens, 1)
          DumpConfigCommand.new
        when "reload-config"
          expect_count(tokens, 1)
          ReloadConfigCommand.new
        when "status"
          expect_count(tokens, 1)
          StatusCommand.new
        when "server-status"
          expect_count(tokens, 1)
          ServerStatusCommand.new
        when "obs-status"
          expect_count(tokens, 1)
          ObsStatusCommand.new
        when "validate-config"
          expect_count(tokens, 1)
          ValidateConfigCommand.new
        when "reconnect"
          expect_count(tokens, 1)
          ReconnectCommand.new
        when "shutdown-server"
          expect_count(tokens, 1)
          ShutdownServerCommand.new
        when "connect"
          expect_count(tokens, 1)
          ConnectCommand.new
        when "disconnect"
          expect_count(tokens, 1)
          DisconnectCommand.new
        when "set-scene", "scene"
          expect_count(tokens, 2)
          SetSceneCommand.new(tokens[1])
        when "mute"
          expect_count(tokens, 2)
          MuteCommand.new(tokens[1])
        when "unmute"
          expect_count(tokens, 2)
          UnmuteCommand.new(tokens[1])
        when "toggle-mute"
          expect_count(tokens, 2)
          ToggleMuteCommand.new(tokens[1])
        when "vol", "volume"
          expect_count(tokens, 3)
          percent = parse_percent(tokens[2])
          VolumeCommand.new(tokens[1], percent)
        else
          raise CommandParseError.new("unknown command: #{command}")
        end
      end

      private def expect_count(tokens : Array(String), expected : Int32) : Nil
        return if tokens.size == expected

        raise CommandParseError.new("wrong argument count for #{tokens[0]}")
      end

      private def parse_percent(value : String) : Int32
        percent = value.to_i?
        raise CommandParseError.new("volume must be an integer from 0 to 100") unless percent
        unless 0 <= percent <= 100
          raise CommandParseError.new("volume must be from 0 to 100")
        end
        percent
      end

      private def tokenize(input : String) : Array(String)
        tokens = [] of String
        current = ""
        in_quote = false
        escaped = false

        input.each_char do |char|
          if escaped
            current += char
            escaped = false
            next
          end

          case char
          when '\\'
            escaped = true
          when '"'
            in_quote = !in_quote
          when ' ', '\t'
            if in_quote
              current += char
            elsif current.size > 0
              tokens << current
              current = ""
            end
          else
            current += char
          end
        end

        raise CommandParseError.new("unterminated quote") if in_quote
        tokens << current if current.size > 0
        tokens
      end
    end
  end
end
