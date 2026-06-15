require "file_utils"
require "../config/config_paths"
require "../domain/errors"

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
      def initialize(@level : LogLevel = LogLevel::Info, @path : String = Config::ConfigPaths.log_path)
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

        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") do |file|
          file.puts("#{Time.utc.to_rfc3339} level=#{label_for(level)} #{redact(message)}")
        end
      rescue
      end

      # Writes a message with a parsed string severity.
      def write(level : String, message : String) : Nil
        write(LogLevel.parse(level), message)
      rescue Domain::CommandParseError
        write(LogLevel::Info, message)
      end

      private def redact(message : String) : String
        message.gsub(/(?i)(password|authentication)=\S+/, "\\1=[redacted]")
      end

      private def label_for(level : LogLevel) : String
        level.to_s.downcase
      end
    end
  end
end
