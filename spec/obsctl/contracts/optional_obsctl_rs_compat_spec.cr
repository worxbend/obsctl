require "file_utils"
require "../../spec_helper"
require "../../support/optional_obsctl_rs_compat"

private def with_obsctl_rs_compat_roots(&)
  root = File.join(Dir.tempdir, "obsctl-rs-compat-#{Random.rand(1_000_000)}")
  local_root = File.join(root, "local")
  sibling_repo = File.join(root, "obsctl-rs")
  sibling_root = File.join(sibling_repo, "spec/fixtures/contracts")
  FileUtils.mkdir_p(local_root)
  FileUtils.mkdir_p(sibling_root)
  yield local_root, sibling_repo, sibling_root
ensure
  FileUtils.rm_rf(root) if root
end

private def write_contract_fixture(root : String, path : String, content : String) : Nil
  full_path = File.join(root, path)
  FileUtils.mkdir_p(File.dirname(full_path))
  File.write(full_path, content)
end

private def write_contract_manifest(root : String, fixture_paths : Array(String)) : Nil
  write_contract_fixture(root, "contract_manifest.yml", <<-YAML)
  version: 1
  fixture_root: spec/fixtures/contracts
  required_directories:
    - cli/human/
    - cli/json/
    - ipc/
  recognized_rust_roots:
    - spec/fixtures/contracts/
    - tests/fixtures/contracts/
    - fixtures/contracts/
  fixtures:
  #{fixture_paths.map { |path| "  - category: #{path.split("/")[0, 2].join("/")}\n    relative_path: #{path}\n    purpose: Test fixture.\n    behavior: current_daemon\n    contains_dropped_reconnect_diagnostic_logs: false" }.join("\n")}
  YAML
end

private def create_required_contract_directories(root : String) : Nil
  ["cli/human", "cli/json", "ipc"].each do |directory|
    FileUtils.mkdir_p(File.join(root, directory))
  end
end

private def with_default_obsctl_rs_compat_env(&) : Nil
  with_env_value(Obsctl::SpecSupport::OptionalObsctlRsCompat::SKIP_ENV, nil) do
    with_env_value(Obsctl::SpecSupport::OptionalObsctlRsCompat::STRICT_ENV, nil) do
      yield
    end
  end
end

private def with_strict_obsctl_rs_compat_env(&) : Nil
  with_env_value(Obsctl::SpecSupport::OptionalObsctlRsCompat::SKIP_ENV, nil) do
    with_env_value(Obsctl::SpecSupport::OptionalObsctlRsCompat::STRICT_ENV, "1") do
      yield
    end
  end
end

private def with_env_value(name : String, value : String?, &) : Nil
  previous = ENV[name]?
  if value
    ENV[name] = value
  else
    ENV.delete(name)
  end

  yield
ensure
  if previous
    ENV[name] = previous
  else
    ENV.delete(name)
  end
end

describe Obsctl::SpecSupport::OptionalObsctlRsCompat do
  it "skips compatibility checks when the sibling repository is absent in default mode" do
    with_default_obsctl_rs_compat_env do
      root = File.join(Dir.tempdir, "obsctl-rs-absent-#{Random.rand(1_000_000)}")
      local_root = File.join(root, "local")
      missing_sibling = File.join(root, "obsctl-rs")
      FileUtils.mkdir_p(local_root)

      Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", missing_sibling).should be_nil
    ensure
      FileUtils.rm_rf(root) if root
    end
  end

  it "skips compatibility checks when the sibling repository has no fixtures in default mode" do
    with_default_obsctl_rs_compat_env do
      root = File.join(Dir.tempdir, "obsctl-rs-default-missing-fixtures-#{Random.rand(1_000_000)}")
      local_root = File.join(root, "local")
      sibling_repo = File.join(root, "obsctl-rs")
      FileUtils.mkdir_p(local_root)
      FileUtils.mkdir_p(sibling_repo)

      Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo).should be_nil
    ensure
      FileUtils.rm_rf(root) if root
    end
  end

  it "reports missing local fixtures, missing obsctl-rs fixtures, and content differences" do
    with_obsctl_rs_compat_roots do |local_root, _sibling_repo, sibling_root|
      write_contract_fixture(local_root, "cli/shared.json", %({"ok":true}))
      write_contract_fixture(local_root, "cli/local_only.json", %({"local":true}))
      write_contract_fixture(local_root, "ipc/ignored.json", %({"ignored":true}))
      write_contract_fixture(sibling_root, "cli/shared.json", %({"ok":false}))
      write_contract_fixture(sibling_root, "cli/sibling_only.json", %({"sibling":true}))
      write_contract_fixture(sibling_root, "ipc/ignored.json", %({"ignored":false}))

      failures = Obsctl::SpecSupport::OptionalObsctlRsCompat.fixture_compatibility_failures(local_root, sibling_root, "cli/")

      failures.should contain("missing from obsctl-rs: cli/local_only.json")
      failures.should contain("missing locally: cli/sibling_only.json")
      failures.should contain("content differs: cli/shared.json")
      failures.join("\n").should_not contain("ipc/ignored.json")
    end
  end

  it "fails clearly when the sibling repository is absent in strict mode" do
    with_strict_obsctl_rs_compat_env do
      root = File.join(Dir.tempdir, "obsctl-rs-strict-absent-#{Random.rand(1_000_000)}")
      local_root = File.join(root, "local")
      missing_sibling = File.join(root, "obsctl-rs")
      FileUtils.mkdir_p(local_root)

      expect_raises(Exception, "sibling repository was not found") do
        Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", missing_sibling, IO::Memory.new)
      end
    ensure
      FileUtils.rm_rf(root) if root
    end
  end

  it "fails clearly when the sibling repo exists without a recognized fixture root in strict mode" do
    with_strict_obsctl_rs_compat_env do
      root = File.join(Dir.tempdir, "obsctl-rs-missing-fixtures-#{Random.rand(1_000_000)}")
      local_root = File.join(root, "local")
      sibling_repo = File.join(root, "obsctl-rs")
      diagnostics = IO::Memory.new
      FileUtils.mkdir_p(local_root)
      FileUtils.mkdir_p(sibling_repo)

      error = expect_raises(Exception, "no recognized contract fixture root") do
        Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo, diagnostics)
      end

      diagnostics.to_s.should contain("sibling repository: #{sibling_repo}")
      diagnostics.to_s.should contain("fixture root: none recognized")
      error.message.to_s.should contain("contract_manifest.yml, cli/human/, cli/json/, and ipc/")
      error.message.to_s.should contain("scripts/bootstrap_obsctl_rs_contract_fixtures")
    ensure
      FileUtils.rm_rf(root) if root
    end
  end

  it "prints the selected sibling repository and fixture root before strict comparison" do
    with_strict_obsctl_rs_compat_env do
      with_obsctl_rs_compat_roots do |local_root, sibling_repo, sibling_root|
        diagnostics = IO::Memory.new
        create_required_contract_directories(local_root)
        create_required_contract_directories(sibling_root)
        write_contract_manifest(local_root, ["cli/json/shared.json"])
        write_contract_manifest(sibling_root, ["cli/json/shared.json"])
        write_contract_fixture(local_root, "cli/json/shared.json", %({"ok":true}))
        write_contract_fixture(sibling_root, "cli/json/shared.json", %({"ok":true}))

        Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo, diagnostics)

        diagnostics.to_s.should contain("obsctl-rs compatibility strict mode:")
        diagnostics.to_s.should contain("sibling repository: #{sibling_repo}")
        diagnostics.to_s.should contain("fixture root: #{sibling_root}")
      end
    end
  end

  it "fails on missing required directories in strict mode before comparing contents" do
    with_strict_obsctl_rs_compat_env do
      with_obsctl_rs_compat_roots do |local_root, sibling_repo, sibling_root|
        create_required_contract_directories(local_root)
        FileUtils.mkdir_p(File.join(sibling_root, "cli/json"))
        FileUtils.mkdir_p(File.join(sibling_root, "ipc"))
        write_contract_manifest(local_root, ["cli/json/shared.json"])
        write_contract_manifest(sibling_root, ["cli/json/shared.json"])
        write_contract_fixture(local_root, "cli/json/shared.json", %({"ok":true}))
        write_contract_fixture(sibling_root, "cli/json/shared.json", %({"ok":false}))

        error = expect_raises(Exception, "contract manifest validation failed") do
          Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo, IO::Memory.new)
        end

        error.message.to_s.should contain("missing required obsctl-rs directories: cli/human/")
        error.message.to_s.should contain("scripts/bootstrap_obsctl_rs_contract_fixtures")
        error.message.to_s.should_not contain("content differs")
      end
    end
  end

  it "fails on manifest-listed missing counterpart fixtures in strict mode" do
    with_strict_obsctl_rs_compat_env do
      with_obsctl_rs_compat_roots do |local_root, sibling_repo, sibling_root|
        create_required_contract_directories(local_root)
        create_required_contract_directories(sibling_root)
        write_contract_manifest(local_root, ["cli/json/shared.json", "cli/json/local_only.json"])
        write_contract_manifest(sibling_root, ["cli/json/shared.json", "cli/json/local_only.json"])
        write_contract_fixture(local_root, "cli/json/shared.json", %({"ok":true}))
        write_contract_fixture(local_root, "cli/json/local_only.json", %({"local":true}))
        write_contract_fixture(sibling_root, "cli/json/shared.json", %({"ok":true}))

        error = expect_raises(Exception, "contract manifest validation failed") do
          Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo, IO::Memory.new)
        end

        error.message.to_s.should contain("missing from obsctl-rs: cli/json/local_only.json")
        error.message.to_s.should contain("recognized roots: spec/fixtures/contracts/")
      end
    end
  end

  it "fails on a stale obsctl-rs contract manifest before comparing contents" do
    with_strict_obsctl_rs_compat_env do
      with_obsctl_rs_compat_roots do |local_root, sibling_repo, sibling_root|
        create_required_contract_directories(local_root)
        create_required_contract_directories(sibling_root)
        write_contract_manifest(local_root, ["cli/json/shared.json"])
        write_contract_manifest(sibling_root, ["cli/json/shared.json", "cli/json/extra.json"])
        write_contract_fixture(local_root, "cli/json/shared.json", %({"ok":true}))
        write_contract_fixture(sibling_root, "cli/json/shared.json", %({"ok":false}))

        error = expect_raises(Exception, "contract manifest validation failed") do
          Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo, IO::Memory.new)
        end

        error.message.to_s.should contain("contract manifest differs: contract_manifest.yml")
        error.message.to_s.should_not contain("content differs")
      end
    end
  end

  it "fails on manifest-listed content differences in strict mode" do
    with_strict_obsctl_rs_compat_env do
      with_obsctl_rs_compat_roots do |local_root, sibling_repo, sibling_root|
        create_required_contract_directories(local_root)
        create_required_contract_directories(sibling_root)
        write_contract_manifest(local_root, ["cli/json/shared.json"])
        write_contract_manifest(sibling_root, ["cli/json/shared.json"])
        write_contract_fixture(local_root, "cli/json/shared.json", %({"ok":true}))
        write_contract_fixture(sibling_root, "cli/json/shared.json", %({"ok":false}))
        write_contract_fixture(sibling_root, "cli/json/sibling_only.json", %({"sibling":true}))

        error = expect_raises(Exception, "obsctl-rs fixture compatibility failed") do
          Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo, IO::Memory.new)
        end

        error.message.to_s.should contain("content differs: cli/json/shared.json")
        error.message.to_s.should_not contain("cli/json/sibling_only.json")
      end
    end
  end

  it "allows an explicit environment skip for dual-repo compatibility checks" do
    with_env_value(Obsctl::SpecSupport::OptionalObsctlRsCompat::SKIP_ENV, "1") do
      with_env_value(Obsctl::SpecSupport::OptionalObsctlRsCompat::STRICT_ENV, "1") do
        root = File.join(Dir.tempdir, "obsctl-rs-skip-#{Random.rand(1_000_000)}")
        local_root = File.join(root, "local")
        sibling_repo = File.join(root, "obsctl-rs")
        FileUtils.mkdir_p(local_root)
        FileUtils.mkdir_p(sibling_repo)

        Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo).should be_nil
      ensure
        FileUtils.rm_rf(root) if root
      end
    end
  end
end
