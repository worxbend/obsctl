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
        raise CommandParseError.new("empty command") if argv.empty?

        name = sanitize_token(argv[0], "command")
        spec = CommandRegistry[name]?
        raise CommandParseError.new("unknown command: #{CommandRegistry.normalize(name)}") unless spec

        arguments = argv[1..]
        spec.validate_arity!(arguments.size)

        sanitized_arguments = Array(String).new(arguments.size)
        arguments.each do |value|
          sanitized_arguments << sanitize_token(value.strip, "target")
        end

        spec.build.call(sanitized_arguments)
      end

      # Parses one command line, including quoted arguments.
      def parse(input : String) : Command
        parse_tokens(tokenize(input))
      end

      private def parse_tokens(tokens : Array(Token)) : Command
        raise CommandParseError.new("empty command") if tokens.empty?

        name = sanitize_token(tokens[0].value, "command")
        spec = CommandRegistry[name]?
        raise CommandParseError.new("unknown command: #{CommandRegistry.normalize(name)}") unless spec

        arguments = tokens[1..]
        spec.validate_arity!(arguments.size)
        reject_quoted_numerics!(spec, arguments)

        sanitized_arguments = Array(String).new(arguments.size)
        arguments.each do |token|
          sanitized_arguments << sanitize_token(token.value.strip, "target")
        end

        spec.build.call(sanitized_arguments)
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
      # Both quote styles group: `"Cam 1"` and `'Cam 1'` name the same scene,
      # and the style that is not open stays literal, so a name containing a
      # double quote can be written `'Cam "A"'`. Inside quotes a backslash
      # escapes the next character; outside quotes a backslash is literal,
      # which keeps names like `Cam\Main` readable without doubling.
      private def tokenize(input : String) : Array(Token)
        tokens = [] of Token
        current = String::Builder.new
        length = 0
        quoted = false
        open_quote : Char? = nil
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
            if open_quote
              escaped = true
            else
              current << char
              length += 1
            end
          when '"', '\''
            if open_quote == char
              open_quote = nil
              quoted = true
            elsif open_quote
              current << char
              length += 1
            else
              open_quote = char
              quoted = true
            end
          when ' ', '\t'
            if open_quote
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

        raise CommandParseError.new("unterminated quote") if open_quote
        flush.call if length > 0 || quoted
        tokens
      end
    end
  end
end
