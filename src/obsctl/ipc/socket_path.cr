require "file_utils"

module Obsctl
  module IPC
    module SocketPath
      DEFAULT_SOCKET_NAME = "obsctl.sock"

      def self.resolve(configured_path : String? = nil, env = ENV) : String
        return File.expand_path(configured_path) if configured_path && !configured_path.empty?

        if runtime_dir = env["XDG_RUNTIME_DIR"]?
          return File.join(runtime_dir, "obsctl", DEFAULT_SOCKET_NAME)
        end

        File.join("/tmp", "obsctl-#{uid}", DEFAULT_SOCKET_NAME)
      end

      def self.ensure_parent(path : String) : Nil
        Dir.mkdir_p(File.dirname(path))
      end

      def self.uid : UInt32
        LibC.getuid
      end
    end
  end
end
