module Obsctl
  module Config
    # Resolves user-scoped config and log paths.
    module ConfigPaths
      DEFAULT_RELATIVE = ".config/obsctl/config.yml"

      # Returns `OBSCTL_CONFIG` when set, otherwise the XDG-style default path.
      def self.default_path(env = ENV) : String
        env["OBSCTL_CONFIG"]? || File.join(home(env), DEFAULT_RELATIVE)
      end

      # Returns the default persisted server log path.
      def self.log_path(env = ENV) : String
        File.join(home(env), ".local/state/obsctl/obsctl.log")
      end

      private def self.home(env) : String
        env["HOME"]? || "."
      end
    end
  end
end
