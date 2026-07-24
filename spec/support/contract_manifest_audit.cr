require "yaml"
require "./optional_obsctl_rs_compat"

module Obsctl
  module SpecSupport
    # Audits the local contract manifest against the fixtures on disk.
    #
    # `OptionalObsctlRsCompat` only validates the manifest in strict mode, when
    # the sibling obsctl-rs repository is present. That leaves the local tree
    # unguarded: a fixture added under spec/fixtures/contracts/ without a
    # manifest entry is invisible to the cross-language contract check, and a
    # manifest entry whose file was deleted fails only on the machine that
    # happens to run strict mode. This audit runs in the normal suite so both
    # drift directions fail immediately.
    module ContractManifestAudit
      # Files that live in the fixture root but are not themselves fixtures.
      NON_FIXTURE_FILES = ["contract_manifest.yml", "README.md"]

      REQUIRED_KEYS = ["version", "fixture_root", "required_directories", "behaviors", "fixtures"]

      # The manifest records whether a fixture carries this telemetry key, so
      # obsctl-rs can assert the same mixed-version behavior. A stale flag would
      # silently weaken that check on both sides.
      TELEMETRY_KEY = "dropped_reconnect_diagnostic_logs"

      def self.fixture_root : String
        File.expand_path("../fixtures/contracts", __DIR__)
      end

      # Returns every audit failure, empty when the manifest is consistent.
      def self.failures(root : String = fixture_root) : Array(String)
        manifest_path = File.join(root, OptionalObsctlRsCompat::MANIFEST_FILENAME)
        return ["missing contract manifest at #{manifest_path}"] unless File.file?(manifest_path)

        begin
          parsed = YAML.parse(File.read(manifest_path))
        rescue ex : YAML::ParseException
          return ["contract manifest is not valid YAML: #{ex.message}"]
        end

        missing_keys = REQUIRED_KEYS.reject { |key| parsed[key]? }
        return ["contract manifest is missing required keys: #{missing_keys.join(", ")}"] unless missing_keys.empty?

        entries = parsed["fixtures"].as_a
        behaviors = parsed["behaviors"].as_h.keys.map(&.as_s)

        failures = [] of String
        failures.concat(structure_failures(entries, behaviors))
        failures.concat(directory_failures(root, parsed["required_directories"].as_a.map(&.as_s)))
        failures.concat(coverage_failures(root, entries))
        failures.concat(telemetry_flag_failures(root, entries))
        failures
      rescue ex : TypeCastError
        ["contract manifest has an unexpected shape: #{ex.message}"]
      end

      # Verifies each entry declares the fields the compat check depends on.
      private def self.structure_failures(entries : Array(YAML::Any), behaviors : Array(String)) : Array(String)
        failures = [] of String
        seen = [] of String

        entries.each_with_index do |entry, index|
          label = entry["relative_path"]?.try(&.as_s?) || "fixtures[#{index}]"

          path = entry["relative_path"]?.try(&.as_s?)
          if path.nil? || path.empty?
            failures << "#{label}: missing relative_path"
            next
          end

          failures << "#{label}: listed more than once" if seen.includes?(path)
          seen << path

          category = entry["category"]?.try(&.as_s?)
          if category.nil? || category.empty?
            failures << "#{label}: missing category"
          elsif !path.starts_with?("#{category}/")
            failures << "#{label}: category #{category} does not match its path"
          end

          purpose = entry["purpose"]?.try(&.as_s?)
          failures << "#{label}: missing purpose" if purpose.nil? || purpose.empty?

          behavior = entry["behavior"]?.try(&.as_s?)
          if behavior.nil? || behavior.empty?
            failures << "#{label}: missing behavior"
          elsif !behaviors.includes?(behavior)
            failures << "#{label}: behavior #{behavior} is not declared under behaviors"
          end

          if entry["contains_#{TELEMETRY_KEY}"]?.try(&.as_bool?).nil?
            failures << "#{label}: contains_#{TELEMETRY_KEY} must be true or false"
          end
        end

        failures
      end

      private def self.directory_failures(root : String, required_directories : Array(String)) : Array(String)
        required_directories
          .reject { |directory| File.directory?(File.join(root, directory)) }
          .map { |directory| "required directory is missing: #{directory}" }
      end

      # The completeness check in both directions.
      private def self.coverage_failures(root : String, entries : Array(YAML::Any)) : Array(String)
        listed = entries.compact_map { |entry| entry["relative_path"]?.try(&.as_s?) }.sort!
        on_disk = OptionalObsctlRsCompat.local_fixture_paths(root)
          .reject { |path| NON_FIXTURE_FILES.includes?(path) }
          .sort!

        unlisted = on_disk - listed
        missing = listed - on_disk

        failures = [] of String
        unless unlisted.empty?
          failures << "fixtures on disk but absent from the manifest: #{unlisted.join(", ")}"
        end
        unless missing.empty?
          failures << "fixtures listed in the manifest but absent from disk: #{missing.join(", ")}"
        end
        failures
      end

      # Keeps the declared telemetry flag honest against the fixture body.
      private def self.telemetry_flag_failures(root : String, entries : Array(YAML::Any)) : Array(String)
        failures = [] of String

        entries.each do |entry|
          path = entry["relative_path"]?.try(&.as_s?)
          declared = entry["contains_#{TELEMETRY_KEY}"]?.try(&.as_bool?)
          next if path.nil? || declared.nil?

          full_path = File.join(root, path)
          next unless File.file?(full_path)

          actual = File.read(full_path).includes?(TELEMETRY_KEY)
          next if actual == declared

          failures << "#{path}: contains_#{TELEMETRY_KEY} is #{declared} but the fixture #{actual ? "does" : "does not"} contain #{TELEMETRY_KEY}"
        end

        failures
      end
    end
  end
end
