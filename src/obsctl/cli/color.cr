require "../domain/errors"

module Obsctl
  module CLI
    # How `--color` was requested on the command line.
    enum ColorMode
      Auto
      Always
      Never

      # Parses the `--color` option value.
      def self.from_option(value : String) : self
        case value.downcase
        when "auto"   then Auto
        when "always" then Always
        when "never"  then Never
        else
          raise Domain::CommandParseError.new("--color must be auto, always, or never")
        end
      end
    end

    # Resolved ANSI palette for human-readable CLI output.
    #
    # Formatters interpolate these unconditionally; when color is disabled every
    # accessor returns an empty string, so a single code path produces both the
    # decorated terminal form and the plain form used for pipes, files, and
    # golden fixtures.
    struct Palette
      RESET        = "\e[0m"
      BOLD         = "\e[1m"
      DIM          = "\e[2m"
      GREEN        = "\e[32m"
      RED          = "\e[31m"
      YELLOW       = "\e[33m"
      CYAN         = "\e[36m"
      BLUE         = "\e[34m"
      MAGENTA      = "\e[35m"
      BRIGHT_WHITE = "\e[97m"

      getter? enabled : Bool

      def initialize(@enabled : Bool = false)
      end

      # Palette that never emits escape sequences.
      def self.monochrome : self
        new(false)
      end

      # Palette that always emits escape sequences.
      def self.colored : self
        new(true)
      end

      # Resolves the palette for one invocation.
      #
      # `Auto` colors only a real terminal, and defers to `NO_COLOR` and
      # `TERM=dumb` so redirected output and dumb terminals stay plain.
      def self.resolve(mode : ColorMode, io : IO, env = ENV) : self
        case mode
        in ColorMode::Always then colored
        in ColorMode::Never  then monochrome
        in ColorMode::Auto   then new(auto_enabled?(io, env))
        end
      end

      private def self.auto_enabled?(io : IO, env) : Bool
        # https://no-color.org: any non-empty value disables color.
        return false if env["NO_COLOR"]?.presence
        return false if env["TERM"]? == "dumb"

        io.is_a?(IO::FileDescriptor) && io.tty?
      end

      {% for name in %w[reset bold dim green red yellow cyan blue magenta bright_white] %}
        # Returns the {{ name.id }} escape sequence, or "" when color is disabled.
        def {{ name.id }} : String
          @enabled ? {{ name.upcase.id }} : ""
        end
      {% end %}
    end
  end
end
