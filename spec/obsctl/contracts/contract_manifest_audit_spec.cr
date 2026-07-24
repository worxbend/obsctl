require "file_utils"
require "../../spec_helper"
require "../../support/contract_manifest_audit"

private def with_audit_root(&)
  root = File.join(Dir.tempdir, "obsctl-manifest-audit-#{Random.rand(1_000_000)}")
  ["cli/human", "cli/json", "ipc"].each { |dir| FileUtils.mkdir_p(File.join(root, dir)) }
  yield root
ensure
  FileUtils.rm_rf(root) if root
end

private def write_audit_fixture(root : String, path : String, content : String = "{}") : Nil
  full_path = File.join(root, path)
  FileUtils.mkdir_p(File.dirname(full_path))
  File.write(full_path, content)
end

private def write_audit_manifest(root : String, entries : String) : Nil
  File.write(File.join(root, "contract_manifest.yml"), <<-YAML)
  version: 1
  fixture_root: spec/fixtures/contracts
  required_directories:
    - cli/human/
    - cli/json/
    - ipc/
  recognized_rust_roots:
    - spec/fixtures/contracts/
  behaviors:
    current_daemon: Fixture represents the current daemon and CLI contract.
  fixtures:
  #{entries}
  YAML
end

private def audit_entry(path : String, category : String? = nil, behavior : String = "current_daemon", telemetry : Bool = false) : String
  <<-ENTRY
    - category: #{category || path.split("/")[0..-2].join("/")}
      relative_path: #{path}
      purpose: Test fixture.
      behavior: #{behavior}
      contains_dropped_reconnect_diagnostic_logs: #{telemetry}
  ENTRY
end

describe Obsctl::SpecSupport::ContractManifestAudit do
  it "reports no failures for the checked-in contract manifest" do
    Obsctl::SpecSupport::ContractManifestAudit.failures.should be_empty
  end

  it "accounts for every fixture in the contract root" do
    root = Obsctl::SpecSupport::ContractManifestAudit.fixture_root
    manifest = YAML.parse(File.read(File.join(root, "contract_manifest.yml")))
    listed = manifest["fixtures"].as_a.map(&.["relative_path"].as_s).sort!
    on_disk = Obsctl::SpecSupport::OptionalObsctlRsCompat.local_fixture_paths(root)
      .reject { |path| Obsctl::SpecSupport::ContractManifestAudit::NON_FIXTURE_FILES.includes?(path) }
      .sort!

    listed.should eq(on_disk)
  end

  it "fails when a fixture on disk is missing from the manifest" do
    with_audit_root do |root|
      write_audit_fixture(root, "ipc/known.json")
      write_audit_fixture(root, "ipc/orphan.json")
      write_audit_manifest(root, audit_entry("ipc/known.json"))

      failures = Obsctl::SpecSupport::ContractManifestAudit.failures(root)
      failures.size.should eq(1)
      failures[0].should contain("absent from the manifest")
      failures[0].should contain("ipc/orphan.json")
    end
  end

  it "fails when the manifest lists a fixture that is not on disk" do
    with_audit_root do |root|
      write_audit_fixture(root, "ipc/known.json")
      write_audit_manifest(root, "#{audit_entry("ipc/known.json")}\n#{audit_entry("ipc/deleted.json")}")

      failures = Obsctl::SpecSupport::ContractManifestAudit.failures(root)
      failures.size.should eq(1)
      failures[0].should contain("absent from disk")
      failures[0].should contain("ipc/deleted.json")
    end
  end

  it "fails when an entry declares a category that does not match its path" do
    with_audit_root do |root|
      write_audit_fixture(root, "ipc/known.json")
      write_audit_manifest(root, audit_entry("ipc/known.json", category: "cli/json"))

      failures = Obsctl::SpecSupport::ContractManifestAudit.failures(root)
      failures.any?(&.includes?("does not match its path")).should be_true
    end
  end

  it "fails when an entry uses a behavior that is not declared" do
    with_audit_root do |root|
      write_audit_fixture(root, "ipc/known.json")
      write_audit_manifest(root, audit_entry("ipc/known.json", behavior: "invented_behavior"))

      failures = Obsctl::SpecSupport::ContractManifestAudit.failures(root)
      failures.any?(&.includes?("is not declared under behaviors")).should be_true
    end
  end

  it "fails when the declared telemetry flag disagrees with the fixture body" do
    with_audit_root do |root|
      write_audit_fixture(root, "ipc/telemetry.json", %({"dropped_reconnect_diagnostic_logs":4}))
      write_audit_manifest(root, audit_entry("ipc/telemetry.json", telemetry: false))

      failures = Obsctl::SpecSupport::ContractManifestAudit.failures(root)
      failures.any?(&.includes?("does contain dropped_reconnect_diagnostic_logs")).should be_true
    end
  end

  it "fails when a required directory is missing" do
    with_audit_root do |root|
      FileUtils.rm_rf(File.join(root, "cli/human"))
      write_audit_fixture(root, "ipc/known.json")
      write_audit_manifest(root, audit_entry("ipc/known.json"))

      failures = Obsctl::SpecSupport::ContractManifestAudit.failures(root)
      failures.any?(&.includes?("required directory is missing: cli/human/")).should be_true
    end
  end

  it "fails when the manifest is missing a required top-level key" do
    with_audit_root do |root|
      File.write(File.join(root, "contract_manifest.yml"), "version: 1\nfixtures: []\n")

      failures = Obsctl::SpecSupport::ContractManifestAudit.failures(root)
      failures.size.should eq(1)
      failures[0].should contain("missing required keys")
    end
  end

  it "fails when the manifest is not valid YAML" do
    with_audit_root do |root|
      File.write(File.join(root, "contract_manifest.yml"), "fixtures:\n  - [unclosed\n")

      failures = Obsctl::SpecSupport::ContractManifestAudit.failures(root)
      failures.size.should eq(1)
      failures[0].should contain("not valid YAML")
    end
  end
end
