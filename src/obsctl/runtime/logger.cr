require "file_utils"
require "../config/config_paths"
require "../domain/errors"
require "./secret_redaction"

module Obsctl
  module Runtime
    # Ordered log severity used by the server runtime logger.
    enum LogLevel
      Debug
      Info
      Warn
      Error

      # Parses a CLI/config log-level string.
      def self.parse(value : String) : LogLevel
        case value.downcase
        when "debug"
          Debug
        when "info"
          Info
        when "warn", "warning"
          Warn
        when "error"
          Error
        else
          raise Domain::CommandParseError.new("invalid log level: #{value}")
        end
      end
    end

    # Small file logger for server lifecycle and command-failure diagnostics.
    class Logger
      # Creates a logger writing to the configured runtime log path.
      def initialize(
        @level : LogLevel = LogLevel::Info,
        @path : String = Config::ConfigPaths.log_path,
        @output : IO? = nil,
      )
        @dropped_writes = Atomic(Int32).new(0)
        @drop_warning_sent = Atomic(Bool).new(false)
      end

      # How many log lines never reached the file because the write failed.
      def dropped_writes : Int32
        @dropped_writes.get
      end

      # Writes a debug-level message when enabled.
      def debug(message : String) : Nil
        write(LogLevel::Debug, message)
      end

      # Writes an info-level message when enabled.
      def info(message : String) : Nil
        write(LogLevel::Info, message)
      end

      # Writes a warn-level message when enabled.
      def warn(message : String) : Nil
        write(LogLevel::Warn, message)
      end

      # Writes an error-level message when enabled.
      def error(message : String) : Nil
        write(LogLevel::Error, message)
      end

      # Writes a message with a typed severity, redacting known sensitive fields.
      def write(level : LogLevel, message : String) : Nil
        return if level.value < @level.value

        line = String.build do |io|
          io << Time.utc.to_rfc3339
          io << " level="
          io << label_for(level)
          io << ' '
          io << self.class.redact_secrets(message)
        end
        write_file(line)
        write_output(line)
      end

      private def write_file(line : String) : Nil
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") do |file|
          file.puts(line)
        end
      rescue ex
        record_dropped_write(ex)
      end

      # A daemon whose log file stopped being writable — disk full, the path
      # rotated away — would otherwise keep "logging" into nothing with no
      # signal anywhere. The warning goes straight to the output sink rather
      # than through `write`, so a broken file sink cannot recurse, and only
      # the first failure is reported: one disk-full event is one problem,
      # not one per log line. Later drops are still counted in
      # `dropped_writes`.
      private def record_dropped_write(error : Exception) : Nil
        @dropped_writes.add(1)
        return if @drop_warning_sent.swap(true)

        warning = "obsctl: writing to log file #{@path} failed (#{error.message}); log lines are being dropped"
        if output = @output
          output.puts(warning)
        else
          STDERR.puts(warning)
        end
      rescue
        # The last-resort sink is broken too; the counter still recorded the drop.
      end

      private def write_output(line : String) : Nil
        @output.try(&.puts(line))
      rescue
      end

      # Writes a message with a parsed string severity.
      def write(level : String, message : String) : Nil
        write(LogLevel.parse(level), message)
      rescue Domain::CommandParseError
        write(LogLevel::Info, message)
      end

      # Redacts secret-like values from public logs and state messages.
      # Delegates to the shared ruleset (which also precompiles the regexes,
      # where this method used to rebuild them on every call).
      def self.redact_secrets(message : String) : String
        SecretRedaction.redact(message)
      end

      private def label_for(level : LogLevel) : String
        case level
        in .debug? then "debug"
        in .info?  then "info"
        in .warn?  then "warn"
        in .error? then "error"
        end
      end
    end
  end
end
