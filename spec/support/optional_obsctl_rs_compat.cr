module Obsctl
  module SpecSupport
    module OptionalObsctlRsCompat
      SKIP_ENV   = "OBSCTL_SKIP_OBSCTL_RS_COMPAT"
      STRICT_ENV = "OBSCTL_STRICT_OBSCTL_RS_COMPAT"

      def self.sibling_repo : String
        File.expand_path("../../../obsctl-rs", __DIR__)
      end

      def self.sibling_present? : Bool
        File.directory?(sibling_repo)
      end

      def self.skip_requested? : Bool
        truthy_env?(SKIP_ENV)
      end

      def self.strict_requested? : Bool
        truthy_env?(STRICT_ENV)
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
        diagnostics : IO = STDERR,
      ) : Nil
        return if skip_requested?
        return unless strict_requested?

        unless File.directory?(repo)
          print_strict_selection(diagnostics, repo, nil)
          raise missing_sibling_repo_message(repo)
        end

        compat_root = fixture_root(repo)
        unless compat_root
          print_strict_selection(diagnostics, repo, nil)
          raise missing_fixture_root_message(repo)
        end

        print_strict_selection(diagnostics, repo, compat_root)
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

      def self.missing_sibling_repo_message(repo : String) : String
        <<-MESSAGE
        obsctl-rs fixture compatibility is running in strict mode, but the sibling repository was not found at #{repo}.
        Create or check out obsctl-rs at that path, or set #{SKIP_ENV}=1 to skip this compatibility check.
        MESSAGE
      end

      def self.missing_fixture_root_message(repo : String) : String
        <<-MESSAGE
        obsctl-rs fixture compatibility is running in strict mode and the sibling repository at #{repo} has no recognized contract fixture root.
        Expected one of:
        #{fixture_candidates(repo).map { |path| "  - #{path}" }.join("\n")}
        Shared contract fixtures should live under that root with cli/ fixtures for CLI output/envelopes and ipc/ fixtures for typed IPC request payloads.
        Set #{SKIP_ENV}=1 to skip this optional compatibility check.
        MESSAGE
      end

      private def self.print_strict_selection(diagnostics : IO, repo : String, fixture_root : String?) : Nil
        diagnostics.puts "obsctl-rs compatibility strict mode:"
        diagnostics.puts "  sibling repository: #{repo}"
        diagnostics.puts "  fixture root: #{fixture_root || "none recognized"}"
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

      private def self.truthy_env?(name : String) : Bool
        value = ENV[name]?
        return false unless value

        normalized = value.strip.downcase
        !normalized.empty? && normalized != "0" && normalized != "false"
      end
    end
  end
end
