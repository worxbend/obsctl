require "file_utils"
require "../domain/errors"

module Obsctl
  module IPC
    module SocketPath
      DEFAULT_SOCKET_NAME = "obsctl.sock"
      PARENT_MODE         = 0o700

      def self.resolve(configured_path : String? = nil, env = ENV) : String
        return File.expand_path(configured_path) if configured_path && !configured_path.empty?

        # Exported-but-empty counts as unset. Trimmed environments — cron,
        # systemd units, containers — hand out `XDG_RUNTIME_DIR=""`, and
        # joining onto an empty string produces the absolute path
        # "/obsctl/obsctl.sock", which the daemon then tries to create a
        # directory for at the filesystem root.
        runtime_dir = env["XDG_RUNTIME_DIR"]?
        if runtime_dir && !runtime_dir.empty?
          return File.join(runtime_dir, "obsctl", DEFAULT_SOCKET_NAME)
        end

        File.join("/tmp", "obsctl-#{uid}", DEFAULT_SOCKET_NAME)
      end

      # Creates the socket's parent directory and checks it is safe to use.
      #
      # Directories this call creates are owner-only: the `/tmp/obsctl-$UID/`
      # fallback sits in a world-writable parent, and one left at the default
      # umask would let any local user replace the socket file even though the
      # socket itself is 0600.
      #
      # A directory that already exists is left alone. It may be a deliberate
      # choice — `server.socket_path: /tmp/obsctl.sock` puts the socket
      # straight into /tmp — and silently chmod'ing a shared directory would be
      # a worse surprise than the problem it solves.
      def self.ensure_parent(path : String) : Nil
        parent = File.dirname(path)
        return create_parent(parent) unless Dir.exists?(parent)

        assert_safe_parent!(parent)
      end

      private def self.create_parent(parent : String) : Nil
        Dir.mkdir_p(parent, PARENT_MODE)
        File.chmod(parent, PARENT_MODE)
      end

      # Refuses a pre-existing directory another user could tamper with.
      #
      # Someone else's directory is only a hazard when they can also add or
      # replace entries in it, so the check is "owned by another user, writable
      # beyond that user, and without the sticky bit that would stop them
      # deleting our socket". That clears /tmp and $XDG_RUNTIME_DIR while still
      # catching a squatted /tmp/obsctl-$UID.
      private def self.assert_safe_parent!(parent : String) : Nil
        info = File.info(parent)
        return if info.owner_id.to_u32 == uid
        return if info.flags.sticky?
        return unless shared_writable?(info)

        raise Domain::IpcConnectionFailed.new(
          "refusing to use socket directory #{parent}: owned by uid #{info.owner_id} and writable by others"
        )
      end

      private def self.shared_writable?(info : File::Info) : Bool
        info.permissions.includes?(File::Permissions::OtherWrite) ||
          info.permissions.includes?(File::Permissions::GroupWrite)
      end

      def self.uid : UInt32
        LibC.getuid
      end
    end
  end
end
