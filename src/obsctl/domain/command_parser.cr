require "./command"
require "./errors"

module Obsctl
  module Domain
    # Parses CLI command text into typed command objects.
    class CommandParser
      MAX_TARGET_TOKEN_LENGTH = 256

      # Commands taking no arguments, keyed by every spelling that reaches them.
      NULLARY = {
        "help"            => -> { HelpCommand.new.as(Command) },
        "quit"            => -> { QuitCommand.new.as(Command) },
        "exit"            => -> { QuitCommand.new.as(Command) },
        "dump-config"     => -> { DumpConfigCommand.new.as(Command) },
        "reload-config"   => -> { ReloadConfigCommand.new.as(Command) },
        "status"          => -> { StatusCommand.new.as(Command) },
        "server-status"   => -> { ServerStatusCommand.new.as(Command) },
        "obs-status"      => -> { ObsStatusCommand.new.as(Command) },
        "validate-config" => -> { ValidateConfigCommand.new.as(Command) },
        "reconnect"       => -> { ReconnectCommand.new.as(Command) },
        "shutdown-server" => -> { ShutdownServerCommand.new.as(Command) },
        "connect"         => -> { ConnectCommand.new.as(Command) },
        "disconnect"      => -> { DisconnectCommand.new.as(Command) },
        "stream"          => -> { ToggleStreamCommand.new.as(Command) },
      }

      # Commands taking exactly one sanitized target token.
      UNARY = {
        "set-scene"        => ->(target : String) { SetSceneCommand.new(target).as(Command) },
        "scene"            => ->(target : String) { SetSceneCommand.new(target).as(Command) },
        "set-profile"      => ->(target : String) { SetProfileCommand.new(target).as(Command) },
        "profile"          => ->(target : String) { SetProfileCommand.new(target).as(Command) },
        "set-collection"   => ->(target : String) { SetSceneCollectionCommand.new(target).as(Command) },
        "collection"       => ->(target : String) { SetSceneCollectionCommand.new(target).as(Command) },
        "scene-collection" => ->(target : String) { SetSceneCollectionCommand.new(target).as(Command) },
        "mute"             => ->(target : String) { MuteCommand.new(target).as(Command) },
        "unmute"           => ->(target : String) { UnmuteCommand.new(target).as(Command) },
        "toggle-mute"      => ->(target : String) { ToggleMuteCommand.new(target).as(Command) },
      }

      RECORD_ACTIONS = {
        "start"  => -> { StartRecordCommand.new.as(Command) },
        "stop"   => -> { StopRecordCommand.new.as(Command) },
        "toggle" => -> { ToggleRecordCommand.new.as(Command) },
        "pause"  => -> { PauseRecordCommand.new.as(Command) },
        "resume" => -> { ResumeRecordCommand.new.as(Command) },
        "status" => -> { RecordStatusCommand.new.as(Command) },
      }

      # Parses one command line, including quoted arguments.
      def parse(input : String) : Command
        stripped = input.strip
        tokens = tokenize(stripped)
        raise CommandParseError.new("empty command") if tokens.empty?

        command = sanitize_command(tokens[0]).lstrip('/').downcase

        if build = NULLARY[command]?
          expect_count(tokens, 1)
          return build.call
        end

        if build = UNARY[command]?
          expect_count(tokens, 2)
          return build.call(sanitize_target(tokens[1]))
        end

        case command
        when "vol", "volume" then parse_volume(tokens, stripped)
        when "rec", "record" then parse_record(tokens)
        else                      raise CommandParseError.new("unknown command: #{command}")
        end
      end

      private def parse_volume(tokens : Array(String), stripped : String) : Command
        expect_count(tokens, 3)
        raise CommandParseError.new("volume percentage must not be quoted") if stripped.ends_with?('"')
        VolumeCommand.new(sanitize_target(tokens[1]), parse_percent(tokens[2]))
      end

      # Bare `rec` keeps its original toggle behavior; a subcommand selects an
      # explicit action.
      private def parse_record(tokens : Array(String)) : Command
        return ToggleRecordCommand.new if tokens.size == 1
        raise CommandParseError.new("wrong argument count for #{tokens[0]}") if tokens.size > 2

        action = sanitize_target(tokens[1]).downcase
        build = RECORD_ACTIONS[action]?
        unless build
          raise CommandParseError.new("unknown record action: #{tokens[1]}; expected #{RECORD_ACTIONS.keys.join(", ")}")
        end

        build.call
      end

      private def expect_count(tokens : Array(String), expected : Int32) : Nil
        return if tokens.size == expected

        raise CommandParseError.new("wrong argument count for #{tokens[0]}")
      end

      private def sanitize_command(value : String) : String
        sanitize_token(value, "command")
      end

      private def sanitize_target(value : String) : String
        sanitize_token(value.strip, "target")
      end

      private def sanitize_token(value : String, label : String) : String
        raise CommandParseError.new("#{label} must not be blank") if value.empty?
        raise CommandParseError.new("#{label} must not contain control characters") if value.each_char.any?(&.control?)
        if value.size > MAX_TARGET_TOKEN_LENGTH
          raise CommandParseError.new("#{label} must be at most #{MAX_TARGET_TOKEN_LENGTH} characters")
        end
        value
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
            if in_quote
              escaped = true
            else
              current += char
            end
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
