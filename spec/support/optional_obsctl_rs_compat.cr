require "yaml"

module Obsctl
  module SpecSupport
    module OptionalObsctlRsCompat
      SKIP_ENV          = "OBSCTL_SKIP_OBSCTL_RS_COMPAT"
      STRICT_ENV        = "OBSCTL_STRICT_OBSCTL_RS_COMPAT"
      MANIFEST_FILENAME = "contract_manifest.yml"
      BOOTSTRAP_HELPER  = "scripts/bootstrap_obsctl_rs_contract_fixtures"

      RECOGNIZED_RUST_ROOTS = [
        "spec/fixtures/contracts/",
        "tests/fixtures/contracts/",
        "fixtures/contracts/",
      ]

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
        RECOGNIZED_RUST_ROOTS.map { |root| File.join(repo, root) }
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
        manifest = ContractManifest.load(local_root)
        manifest_failures = manifest_validation_failures(local_root, compat_root, manifest, prefix)
        unless manifest_failures.empty?
          raise "obsctl-rs contract manifest validation failed for #{prefix} fixtures:\n#{manifest_failures.join("\n")}\n#{bootstrap_guidance(repo)}"
        end

        failures = manifest_fixture_compatibility_failures(local_root, compat_root, manifest, prefix)
        return if failures.empty?

        raise "obsctl-rs fixture compatibility failed for #{prefix} fixtures:\n#{failures.join("\n")}\n#{bootstrap_guidance(repo)}"
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

      def self.manifest_validation_failures(
        local_root : String,
        compat_root : String,
        manifest : ContractManifest,
        prefix : String,
      ) : Array(String)
        manifest_paths = manifest.fixture_paths(prefix)
        missing_local_directories = missing_required_directories(local_root, manifest.required_directories)
        missing_compat_directories = missing_required_directories(compat_root, manifest.required_directories)
        missing_local_fixtures = manifest_paths.reject { |path| File.file?(File.join(local_root, path)) }
        missing_compat_fixtures = manifest_paths.reject { |path| File.file?(File.join(compat_root, path)) }
        local_manifest_path = File.join(local_root, MANIFEST_FILENAME)
        compat_manifest_path = File.join(compat_root, MANIFEST_FILENAME)

        failures = [] of String
        if !File.file?(compat_manifest_path)
          failures << "missing from obsctl-rs: #{MANIFEST_FILENAME}"
        elsif normalize_fixture(local_manifest_path) != normalize_fixture(compat_manifest_path)
          failures << "contract manifest differs: #{MANIFEST_FILENAME}"
        end
        failures << "missing required local directories: #{format_paths(missing_local_directories)}" unless missing_local_directories.empty?
        failures << "missing required obsctl-rs directories: #{format_paths(missing_compat_directories)}" unless missing_compat_directories.empty?
        failures << "missing local manifest-listed fixtures: #{format_paths(missing_local_fixtures)}" unless missing_local_fixtures.empty?
        failures << "missing from obsctl-rs: #{format_paths(missing_compat_fixtures)}" unless missing_compat_fixtures.empty?
        failures
      end

      def self.manifest_fixture_compatibility_failures(
        local_root : String,
        compat_root : String,
        manifest : ContractManifest,
        prefix : String,
      ) : Array(String)
        changed = manifest.fixture_paths(prefix).select do |path|
          normalize_fixture(File.join(local_root, path)) != normalize_fixture(File.join(compat_root, path))
        end

        failures = [] of String
        failures << "content differs: #{format_paths(changed)}" unless changed.empty?
        failures
      end

      def self.missing_sibling_repo_message(repo : String) : String
        <<-MESSAGE
        obsctl-rs fixture compatibility is running in strict mode, but the sibling repository was not found at #{repo}.
        Create or check out obsctl-rs at that path, then run #{BOOTSTRAP_HELPER} #{repo} to copy the Crystal contract fixtures.
        Set #{SKIP_ENV}=1 to skip this optional compatibility check.
        MESSAGE
      end

      def self.missing_fixture_root_message(repo : String) : String
        <<-MESSAGE
        obsctl-rs fixture compatibility is running in strict mode and the sibling repository at #{repo} has no recognized contract fixture root.
        Expected one of:
        #{fixture_candidates(repo).map { |path| "  - #{path}" }.join("\n")}
        Shared contract fixtures should live under that root with #{MANIFEST_FILENAME}, cli/human/, cli/json/, and ipc/.
        Run #{BOOTSTRAP_HELPER} #{repo} to create the default spec/fixtures/contracts/ root.
        Set #{SKIP_ENV}=1 to skip this optional compatibility check.
        MESSAGE
      end

      struct ContractManifest
        getter required_directories : Array(String)
        getter fixture_paths : Array(String)

        def initialize(@required_directories : Array(String), @fixture_paths : Array(String))
        end

        def self.load(root : String) : self
          path = File.join(root, MANIFEST_FILENAME)
          raise "missing local contract manifest at #{path}\n#{OptionalObsctlRsCompat.bootstrap_guidance}" unless File.file?(path)

          parsed = YAML.parse(File.read(path))
          required_directories = parsed["required_directories"].as_a.map(&.as_s)
          fixture_paths = parsed["fixtures"].as_a.map { |fixture| fixture["relative_path"].as_s }.sort
          new(required_directories, fixture_paths)
        rescue ex : KeyError | TypeCastError | YAML::ParseException
          raise "invalid local contract manifest at #{path}: #{ex.message}\n#{OptionalObsctlRsCompat.bootstrap_guidance}"
        end

        def fixture_paths(prefix : String) : Array(String)
          @fixture_paths.select { |path| path.starts_with?(prefix) }.sort
        end
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

      private def self.missing_required_directories(root : String, required_directories : Array(String)) : Array(String)
        required_directories.reject { |directory| File.directory?(File.join(root, directory)) }
      end

      private def self.normalize_fixture(path : String) : String
        File.read(path).strip
      end

      private def self.format_paths(paths : Array(String)) : String
        paths.join(", ")
      end

      def self.bootstrap_guidance(repo : String = sibling_repo) : String
        "Run #{BOOTSTRAP_HELPER} #{repo}; recognized roots: #{RECOGNIZED_RUST_ROOTS.join(", ")}."
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
