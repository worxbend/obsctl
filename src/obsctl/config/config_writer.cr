require "file_utils"
require "./config"

module Obsctl
  module Config
    # Writes config files with backup and atomic-replace semantics.
    class ConfigWriter
      # Writes the default config, backing up an existing file when present.
      def write_default(path : String) : Nil
        write_atomic(path, Config.default.to_yaml, backup: File.exists?(path))
      end

      # Writes a typed config object to disk.
      def write(path : String, config : Config, backup : Bool = true) : Nil
        write_atomic(path, config.to_yaml, backup: backup)
      end

      # Writes raw config contents through a temporary file and final rename.
      def write_atomic(path : String, contents : String, backup : Bool = true) : Nil
        directory = File.dirname(path)
        FileUtils.mkdir_p(directory)
        if backup && File.exists?(path)
          timestamp = Time.utc.to_s("%Y%m%d%H%M%S")
          FileUtils.cp(path, "#{path}.bak.#{timestamp}")
        end
        temp = "#{path}.tmp.#{Process.pid}"
        File.write(temp, contents)
        File.rename(temp, path)
      ensure
        File.delete(temp) if temp && File.exists?(temp)
      end
    end
  end
end
