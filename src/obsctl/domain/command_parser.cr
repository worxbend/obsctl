require "./command"
require "./command_registry"
require "./errors"

module Obsctl
  module Domain
    # Turns command input into typed command objects.
    #
    # There are two entry points because there are two kinds of caller. The CLI
    # already has its arguments split by the kernel and passes them through
    # untouched; the TUI palette has a single line of text and tokenizes first.
    # Argument values never round-trip through a quoted string, so names
    # containing quotes, tabs, or backslashes survive intact.
    class CommandParser
      MAX_TARGET_TOKEN_LENGTH = 256

      # One token, and whether the writer wrapped it in quotes.
      record Token, value : String, quoted : Bool = false

      # Parses an already-split argument vector, e.g. `["scene", "Main Camera"]`.
      #
      # Shell words arrive with their quoting already resolved, so nothing here
      # is treated as quoted.
      def parse(argv : Array(String)) : Command
        parse_tokens(argv.map { |value| Token.new(value) })
      end

      # Parses one command line, including quoted arguments.
      def parse(input : String) : Command
        parse_tokens(tokenize(input.strip))
      end

      private def parse_tokens(tokens : Array(Token)) : Command
        raise CommandParseError.new("empty command") if tokens.empty?

        name = sanitize_token(tokens[0].value, "command")
        spec = CommandRegistry[name]?
        raise CommandParseError.new("unknown command: #{CommandRegistry.normalize(name)}") unless spec

        arguments = tokens[1..]
        spec.validate_arity!(arguments.map(&.value))
        reject_quoted_numerics!(spec, arguments)

        spec.build.call(arguments.map { |token| sanitize_token(token.value.strip, "target") })
      end

      # A percentage is a number, not a name, so quoting one is a mistake worth
      # reporting rather than silently accepting. obsctl-rs rejects it too, and
      # the contract fixtures pin both implementations to the same answer.
      private def reject_quoted_numerics!(spec : CommandSpec, arguments : Array(Token)) : Nil
        spec.arguments.each_with_index do |kind, index|
          next unless kind.percent?
          next unless arguments[index]?.try(&.quoted)

          raise CommandParseError.new("volume percentage must not be quoted")
        end
      end

      private def sanitize_token(value : String, label : String) : String
        raise CommandParseError.new("#{label} must not be blank") if value.empty?
        raise CommandParseError.new("#{label} must not contain control characters") if value.each_char.any?(&.control?)
        if value.size > MAX_TARGET_TOKEN_LENGTH
          raise CommandParseError.new("#{label} must be at most #{MAX_TARGET_TOKEN_LENGTH} characters")
        end
        value
      end

      # Splits a palette line on unquoted whitespace.
      #
      # Inside double quotes a backslash escapes the next character, so a name
      # may contain quotes and spaces. Outside quotes a backslash is literal,
      # which keeps names like `Cam\Main` readable without doubling.
      private def tokenize(input : String) : Array(Token)
        tokens = [] of Token
        current = String::Builder.new
        length = 0
        quoted = false
        in_quote = false
        escaped = false

        flush = -> do
          tokens << Token.new(current.to_s, quoted)
          current = String::Builder.new
          length = 0
          quoted = false
        end

        input.each_char do |char|
          if escaped
            current << char
            length += 1
            escaped = false
            next
          end

          case char
          when '\\'
            if in_quote
              escaped = true
            else
              current << char
              length += 1
            end
          when '"'
            in_quote = !in_quote
            quoted = true
          when ' ', '\t'
            if in_quote
              current << char
              length += 1
            elsif length > 0 || quoted
              flush.call
            end
          else
            current << char
            length += 1
          end
        end

        raise CommandParseError.new("unterminated quote") if in_quote
        flush.call if length > 0 || quoted
        tokens
      end
    end
  end
end
