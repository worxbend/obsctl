require "file_utils"
require "./config"

module Obsctl
  module Config
    # Writes config files with backup and atomic-replace semantics.
    class ConfigWriter
      # Permissions for a config file this writer creates from nothing.
      #
      # Owner-only, because a config may carry `connection.password` in
      # plaintext — the schema only warns about that, it does not forbid it.
      # An existing file's own permissions win over this; see `write_atomic`.
      DEFAULT_PERMISSIONS = File::Permissions.new(0o600)

      # Writes the default config, backing up an existing file when present.
      def write_default(path : String) : Nil
        write_atomic(path, Config.default.to_yaml, backup: File.exists?(path))
      end

      # Writes a typed config object to disk.
      def write(path : String, config : Config, backup : Bool = true) : Nil
        write_atomic(path, config.to_yaml, backup: backup)
      end

      # Writes raw config contents through a temporary file and final rename.
      #
      # Returns the path of the backup copy it made, or nil when it made none,
      # so a caller that needs to tell the user where the old file went does not
      # have to reconstruct the timestamped name — and cannot get it wrong when
      # its own clock reading lands on the other side of a second boundary.
      def write_atomic(path : String, contents : String, backup : Bool = true) : String?
        created_backup = nil
        directory = File.dirname(path)
        FileUtils.mkdir_p(directory)
        # A rename replaces the file wholesale, so the destination's own
        # permissions are gone afterwards. Read them first and re-apply, or a
        # user who ran `chmod 600` on a config holding an OBS password silently
        # gets it back at the process umask (0644 on a typical system) the next
        # time anything writes the file.
        permissions = existing_permissions(path) || DEFAULT_PERMISSIONS
        if backup && File.exists?(path)
          timestamp = Time.utc.to_s("%Y%m%d%H%M%S")
          backup_path = "#{path}.bak.#{timestamp}"
          FileUtils.cp(path, backup_path)
          # The backup holds the same secrets as the original.
          File.chmod(backup_path, permissions)
          created_backup = backup_path
        end
        temp = "#{path}.tmp.#{Process.pid}"
        File.write(temp, contents)
        # Before the rename, so the file is never briefly readable at the
        # umask default under its final name.
        File.chmod(temp, permissions)
        File.rename(temp, path)
        created_backup
      ensure
        File.delete(temp) if temp && File.exists?(temp)
      end

      # Returns the permissions of an existing config file, or nil when there
      # is nothing there yet (or it cannot be inspected).
      private def existing_permissions(path : String) : File::Permissions?
        File.info(path).permissions if File.exists?(path)
      rescue
        nil
      end
    end
  end
end
