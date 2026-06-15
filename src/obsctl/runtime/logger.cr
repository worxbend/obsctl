require "file_utils"
require "../config/config_paths"
require "../domain/errors"

module Obsctl
  module Runtime
    enum LogLevel
      Debug
      Info
      Warn
      Error

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

    class Logger
      def initialize(@level : LogLevel = LogLevel::Info, @path : String = Config::ConfigPaths.log_path)
      end

      def debug(message : String) : Nil
        write(LogLevel::Debug, message)
      end

      def info(message : String) : Nil
        write(LogLevel::Info, message)
      end

      def warn(message : String) : Nil
        write(LogLevel::Warn, message)
      end

      def error(message : String) : Nil
        write(LogLevel::Error, message)
      end

      def write(level : LogLevel, message : String) : Nil
        return if level.value < @level.value

        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") do |file|
          file.puts("#{Time.utc.to_rfc3339} level=#{label_for(level)} #{redact(message)}")
        end
      rescue
      end

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
