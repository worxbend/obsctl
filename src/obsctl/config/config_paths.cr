module Obsctl
  module Config
    module ConfigPaths
      DEFAULT_RELATIVE = ".config/obsctl/config.yml"

      def self.default_path(env = ENV) : String
        env["OBSCTL_CONFIG"]? || File.join(home(env), DEFAULT_RELATIVE)
      end

      def self.log_path(env = ENV) : String
        File.join(home(env), ".local/state/obsctl/obsctl.log")
      end

      private def self.home(env) : String
        env["HOME"]? || "."
      end
    end
  end
end
