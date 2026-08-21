require "file_utils"
require "json"
require "../../spec_helper"
require "../../../src/obsctl/config/config_inspector"

private def with_inspector_config(contents : String? = nil, &)
  path = File.tempname("obsctl-inspector", ".yml")
  if contents
    File.write(path, contents)
  else
    Obsctl::Config::ConfigWriter.new.write(path, Obsctl::Config::Config.default, backup: false)
  end
  yield path
ensure
  if path
    File.delete(path) if File.exists?(path)
    Dir.glob("#{path}.bak.*").each { |backup| File.delete(backup) }
  end
end

private def entry_for(entries : Array(Obsctl::Config::ConfigInspector::Entry), key : String)
  entries.find!(&.key.== key)
end

describe Obsctl::Config::ConfigInspector do
  describe ".flatten" do
    it "flattens nested mappings into dotted key paths" do
      flat = Obsctl::Config::ConfigInspector.flatten("connection:\n  host: 1.2.3.4\n  port: 4455\n")
      flat["connection.host"].should eq("1.2.3.4")
      flat["connection.port"].should eq("4455")
    end

    it "renders sequences inline so reordering is not a phantom change" do
      flat = Obsctl::Config::ConfigInspector.flatten("scenes:\n  items:\n    - a\n    - b\n")
      flat["scenes.items"].should eq("[a, b]")
    end

    it "renders explicit nulls rather than dropping the key" do
      Obsctl::Config::ConfigInspector.flatten("ui:\n  locale:\n")["ui.locale"].should eq("null")
    end
  end

  describe ".explain" do
    it "attributes values written in the file to the file" do
      with_inspector_config do |path|
        entries = Obsctl::Config::ConfigInspector.explain(path)
        entry_for(entries, "connection.port").source.file?.should be_true
        entry_for(entries, "connection.port").value.should eq("4455")
      end
    end

    it "attributes values absent from the file to the defaults" do
      with_inspector_config("version: 1\nconnection:\n  host: 10.0.0.5\n") do |path|
        entries = Obsctl::Config::ConfigInspector.explain(path)
        entry_for(entries, "connection.host").source.file?.should be_true
        entry_for(entries, "connection.host").value.should eq("10.0.0.5")
        entry_for(entries, "connection.port").source.default?.should be_true
      end
    end

    it "redacts a plaintext password instead of printing it" do
      # `config explain` goes to stdout, which ends up in scrollback, CI logs
      # and screen shares; the credential must not travel with it.
      with_inspector_config("version: 1\nconnection:\n  password: hunter2\n") do |path|
        entry = entry_for(Obsctl::Config::ConfigInspector.explain(path), "connection.password")
        entry.value.should eq(Obsctl::Config::ConfigInspector::REDACTED)
        entry.source.file?.should be_true
      end
    end

    it "still prints password_env, which names a variable rather than holding a secret" do
      with_inspector_config("version: 1\nconnection:\n  password_env: MY_OBS_PASSWORD\n") do |path|
        entry_for(Obsctl::Config::ConfigInspector.explain(path), "connection.password_env")
          .value.should eq("MY_OBS_PASSWORD")
      end
    end

    it "returns entries sorted by key" do
      with_inspector_config do |path|
        keys = Obsctl::Config::ConfigInspector.explain(path).map(&.key)
        keys.should eq(keys.sort)
      end
    end

    it "serializes every entry field" do
      with_inspector_config do |path|
        parsed = JSON.parse(Obsctl::Config::ConfigInspector.explain(path).to_json).as_a
        parsed.first["key"].as_s.should_not be_empty
        ["default", "file"].should contain(parsed.first["source"].as_s)
      end
    end
  end

  describe ".diff" do
    it "reports nothing when the file matches the defaults" do
      with_inspector_config do |path|
        Obsctl::Config::ConfigInspector.diff(path).should be_empty
      end
    end

    it "reports only the keys that depart from the defaults" do
      with_inspector_config("version: 1\nui:\n  theme: nord\n") do |path|
        changes = Obsctl::Config::ConfigInspector.diff(path)
        changes.size.should eq(1)
        changes[0].key.should eq("ui.theme")
        changes[0].default_value.should eq("default")
        changes[0].current_value.should eq("nord")
      end
    end

    it "redacts a plaintext password in the reported change" do
      with_inspector_config("version: 1\nconnection:\n  password: hunter2\n") do |path|
        change = Obsctl::Config::ConfigInspector.diff(path).find!(&.key.== "connection.password")
        change.current_value.should eq(Obsctl::Config::ConfigInspector::REDACTED)
      end
    end
  end

  describe ".migrate" do
    it "reports no change for a config already in canonical form" do
      with_inspector_config do |path|
        migration = Obsctl::Config::ConfigInspector.migrate(path)
        migration.changed.should be_false
        migration.dropped_keys.should be_empty
        migration.backup_path.should be_nil
      end
    end

    it "drops top-level keys the current schema does not recognize" do
      with_inspector_config("version: 1\nlegacy_setting: true\nui:\n  theme: nord\n") do |path|
        migration = Obsctl::Config::ConfigInspector.migrate(path)

        migration.changed.should be_true
        migration.dropped_keys.should contain("legacy_setting")
        File.read(path).should_not contain("legacy_setting")
        Obsctl::Config::ConfigLoader.new.load(path).ui.theme.should eq("nord")
      end
    end

    it "preserves the file and reports the same drops under dry run" do
      with_inspector_config("version: 1\nlegacy_setting: true\n") do |path|
        before = File.read(path)
        migration = Obsctl::Config::ConfigInspector.migrate(path, dry_run: true)

        migration.changed.should be_true
        migration.dropped_keys.should contain("legacy_setting")
        migration.backup_path.should be_nil
        File.read(path).should eq(before)
      end
    end

    it "backs up the original before rewriting it" do
      with_inspector_config("version: 1\nlegacy_setting: true\n") do |path|
        migration = Obsctl::Config::ConfigInspector.migrate(path)

        backup = migration.backup_path.not_nil!
        Dir.glob("#{path}.bak.*").should_not be_empty
        backup.should start_with("#{path}.bak.")
      end
    end

    it "reports keys the canonical schema adds" do
      with_inspector_config("version: 1\nui:\n  theme: nord\n") do |path|
        migration = Obsctl::Config::ConfigInspector.migrate(path, dry_run: true)
        migration.added_keys.should contain("connection.port")
      end
    end

    it "raises when the config file does not exist" do
      expect_raises(Obsctl::Domain::ConfigNotFound) do
        Obsctl::Config::ConfigInspector.migrate("/tmp/obsctl-inspector-absent-#{Random.rand(1_000_000)}.yml")
      end
    end

    it "still refuses a config that is invalid beyond unknown keys" do
      with_inspector_config("version: 1\nconnection:\n  port: 70000\n") do |path|
        expect_raises(Obsctl::Domain::ConfigInvalid) do
          Obsctl::Config::ConfigInspector.migrate(path)
        end
      end
    end
  end
end
