module Obsctl
  module SpecSupport
    module OptionalObsctlRsCompat
      SKIP_ENV = "OBSCTL_SKIP_OBSCTL_RS_COMPAT"

      def self.sibling_repo : String
        File.expand_path("../../../obsctl-rs", __DIR__)
      end

      def self.sibling_present? : Bool
        File.directory?(sibling_repo)
      end

      def self.skip_requested? : Bool
        value = ENV[SKIP_ENV]?
        return false unless value

        normalized = value.strip.downcase
        !normalized.empty? && normalized != "0" && normalized != "false"
      end

      def self.fixture_candidates(repo : String = sibling_repo) : Array(String)
        [
          File.join(repo, "spec/fixtures/contracts"),
          File.join(repo, "tests/fixtures/contracts"),
          File.join(repo, "fixtures/contracts"),
        ]
      end

      def self.fixture_root(repo : String = sibling_repo) : String?
        fixture_candidates(repo).find { |path| File.directory?(path) }
      end

      def self.local_fixture_paths(root : String) : Array(String)
        prefix_size = root.size + 1
        Dir.glob(File.join(root, "**", "*"))
          .select { |path| File.file?(path) }
          .map { |path| path[prefix_size..] }
          .sort
      end

      def self.assert_compatible!(
        local_root : String,
        prefix : String,
        repo : String = sibling_repo,
      ) : Nil
        return if skip_requested?
        return unless File.directory?(repo)

        compat_root = fixture_root(repo)
        unless compat_root
          raise missing_fixture_root_message(repo)
        end

        failures = fixture_compatibility_failures(local_root, compat_root, prefix)
        return if failures.empty?

        raise "obsctl-rs fixture compatibility failed for #{prefix} fixtures:\n#{failures.join("\n")}"
      end

      def self.fixture_compatibility_failures(
        local_root : String,
        compat_root : String,
        prefix : String,
      ) : Array(String)
        local_paths = prefixed_fixture_paths(local_root, prefix)
        compat_paths = prefixed_fixture_paths(compat_root, prefix)
        missing_in_compat = local_paths - compat_paths
        missing_locally = compat_paths - local_paths
        common_paths = local_paths.select { |path| compat_paths.includes?(path) }
        changed = common_paths.select do |path|
          normalize_fixture(File.join(local_root, path)) != normalize_fixture(File.join(compat_root, path))
        end

        failures = [] of String
        failures << "missing from obsctl-rs: #{format_paths(missing_in_compat)}" unless missing_in_compat.empty?
        failures << "missing locally: #{format_paths(missing_locally)}" unless missing_locally.empty?
        failures << "content differs: #{format_paths(changed)}" unless changed.empty?
        failures
      end

      def self.missing_fixture_root_message(repo : String) : String
        <<-MESSAGE
        obsctl-rs sibling repository exists at #{repo}, but no recognized contract fixture root was found.
        Expected one of:
        #{fixture_candidates(repo).map { |path| "  - #{path}" }.join("\n")}
        Set #{SKIP_ENV}=1 to skip this optional compatibility check.
        MESSAGE
      end

      private def self.prefixed_fixture_paths(root : String, prefix : String) : Array(String)
        local_fixture_paths(root)
          .select { |path| path.starts_with?(prefix) }
          .sort
      end

      private def self.normalize_fixture(path : String) : String
        File.read(path).strip
      end

      private def self.format_paths(paths : Array(String)) : String
        paths.join(", ")
      end
    end
  end
end
