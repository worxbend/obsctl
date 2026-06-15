require "../config/config_paths"

module Obsctl
  module Runtime
    enum LogLevel
      Debug
      Info
      Warn
      Error
    end

    class Logger
      def initialize(@level : LogLevel = LogLevel::Info, @path : String = Config::ConfigPaths.log_path)
      end

      def info(message : String) : Nil
        write("info", message)
      end

      def warn(message : String) : Nil
        write("warn", message)
      end

      def error(message : String) : Nil
        write("error", message)
      end

      private def write(level : String, message : String) : Nil
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") do |file|
          file.puts("#{Time.utc.to_rfc3339} level=#{level} #{redact(message)}")
        end
      rescue
      end

      private def redact(message : String) : String
        message.gsub(/(?i)(password|authentication)=\S+/, "\\1=[redacted]")
      end
    end
  end
end
