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
        Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", missing_sibling)
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
      FileUtils.mkdir_p(local_root)
      FileUtils.mkdir_p(sibling_repo)

      expect_raises(Exception, "no recognized contract fixture root") do
        Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo)
      end
    ensure
      FileUtils.rm_rf(root) if root
    end
  end

  it "fails on missing counterpart fixtures and content differences in strict mode" do
    with_strict_obsctl_rs_compat_env do
      with_obsctl_rs_compat_roots do |local_root, sibling_repo, sibling_root|
        write_contract_fixture(local_root, "cli/shared.json", %({"ok":true}))
        write_contract_fixture(local_root, "cli/local_only.json", %({"local":true}))
        write_contract_fixture(sibling_root, "cli/shared.json", %({"ok":false}))
        write_contract_fixture(sibling_root, "cli/sibling_only.json", %({"sibling":true}))

        error = expect_raises(Exception, "obsctl-rs fixture compatibility failed") do
          Obsctl::SpecSupport::OptionalObsctlRsCompat.assert_compatible!(local_root, "cli/", sibling_repo)
        end

        error.message.to_s.should contain("missing from obsctl-rs: cli/local_only.json")
        error.message.to_s.should contain("missing locally: cli/sibling_only.json")
        error.message.to_s.should contain("content differs: cli/shared.json")
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
