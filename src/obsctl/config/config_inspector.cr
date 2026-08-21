require "json"
require "yaml"
require "./config"
require "./config_loader"
require "./config_schema"
require "./config_writer"
require "../domain/errors"
require "../runtime/logger"

module Obsctl
  module Config
    # Answers three questions about a config file that the schema alone cannot:
    # where each effective value came from (`explain`), how the file departs
    # from the defaults (`diff`), and what rewriting it in the current schema
    # would change (`migrate`).
    #
    # All three work on dotted key paths flattened from the canonical YAML
    # serialization, so they stay correct as the schema grows without needing a
    # hand-maintained key list.
    module ConfigInspector
      # Stand-in printed instead of a secret's real value.
      REDACTED = "[redacted]"

      # Leaf key names whose value is a credential rather than a setting.
      #
      # Reuses the pattern the log and IPC scrubbers already share so a new
      # secret-shaped setting is hidden on every output path at once. Anchored
      # on the whole leaf name so `password_env` — which holds the *name* of an
      # environment variable, not its value — keeps printing normally.
      SENSITIVE_LEAF_KEY = Regex.new("\\A#{Runtime::Logger::SENSITIVE_KEY_PATTERN}\\z", Regex::Options::IGNORE_CASE)

      # Where an effective value came from.
      enum Source
        Default
        File

        def label : String
          case self
          in .default? then "default"
          in .file?    then "file"
          end
        end
      end

      record Entry, key : String, value : String, source : Source do
        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "key", key
            json.field "value", value
            json.field "source", source.label
          end
        end
      end

      record Change, key : String, default_value : String?, current_value : String? do
        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "key", key
            json.field "default", default_value
            json.field "current", current_value
          end
        end
      end

      record Migration,
        changed : Bool,
        dropped_keys : Array(String),
        added_keys : Array(String),
        backup_path : String? = nil do
        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "changed", changed
            json.field "dropped_keys", dropped_keys
            json.field "added_keys", added_keys
            json.field "backup_path", backup_path
          end
        end
      end

      # Returns every effective setting with the source that supplied it.
      def self.explain(path : String) : Array(Entry)
        effective = flatten(ConfigLoader.new.load(path).to_yaml)
        from_file = flatten(File.read(path)).keys

        effective.map do |key, value|
          Entry.new(key, redact(key, value), from_file.includes?(key) ? Source::File : Source::Default)
        end.sort_by!(&.key)
      end

      # Returns the settings where the file departs from the defaults.
      #
      # A key present in only one side is still a change: `default` or
      # `current` is null to say which side lacks it.
      def self.diff(path : String) : Array(Change)
        defaults = flatten(Config.default.to_yaml)
        current = flatten(ConfigLoader.new.load(path).to_yaml)

        (defaults.keys | current.keys).sort!.compact_map do |key|
          default_value = defaults[key]?
          current_value = current[key]?
          next if default_value == current_value

          Change.new(key, redact(key, default_value), redact(key, current_value))
        end
      end

      # Rewrites the file in the current canonical schema.
      #
      # `dry_run` reports what would change without touching the file. Keys the
      # current schema does not recognize are dropped, which is the point of
      # the command: it is how a config written for an older obsctl stops
      # carrying settings that no longer do anything.
      def self.migrate(path : String, dry_run : Bool = false, writer : ConfigWriter = ConfigWriter.new) : Migration
        raise Domain::ConfigNotFound.new(path) unless File.exists?(path)

        original = File.read(path)
        # Deliberately not ConfigLoader: it rejects unknown top-level keys, and
        # a config carrying those is the case migrate exists to repair. Unknown
        # sections are stripped first, then the result is validated normally.
        config = Config.from_yaml(strip_unknown_top_level(original))
        ConfigSchema.validate!(config)
        canonical = config.to_yaml

        before = flatten(original).keys
        after = flatten(canonical).keys
        dropped = (before - after).sort!
        added = (after - before).sort!
        changed = original != canonical

        return Migration.new(changed, dropped, added) if dry_run || !changed

        backup_path = writer.write_atomic(path, canonical, backup: true)
        Migration.new(true, dropped, added, backup_path)
      end

      # Re-emits the document with only the top-level sections the current
      # schema recognizes.
      private def self.strip_unknown_top_level(yaml : String) : String
        root = YAML.parse(yaml).as_h?
        return yaml unless root

        kept = root.select { |key, _| Config::ALLOWED_TOP_LEVEL_KEYS.includes?(key.as_s? || key.to_s) }
        return yaml if kept.size == root.size

        YAML::Any.new(kept).to_yaml
      rescue ex : YAML::ParseException
        raise Domain::ConfigInvalid.new("invalid YAML: #{ex.message}")
      end

      # Replaces a secret's value with `REDACTED`, leaving other values alone.
      #
      # `config explain` and `config diff` print straight to stdout, which ends
      # up in scrollback, CI logs and screen shares; a plaintext
      # `connection.password` must not travel with it.
      private def self.redact(key : String, value : String?) : String?
        return value if value.nil?
        SENSITIVE_LEAF_KEY.matches?(key.split('.').last) ? REDACTED : value
      end

      # Flattens a YAML document into dotted key paths.
      #
      # Sequences are rendered as a single inline value rather than indexed
      # keys: aliases and shortcuts read better as one line, and an index-based
      # key path would make reordering a list look like a settings change.
      def self.flatten(yaml : String) : Hash(String, String)
        result = {} of String => String
        parsed = YAML.parse(yaml)
        walk(parsed, nil, result)
        result
      rescue ex : YAML::ParseException
        raise Domain::ConfigInvalid.new("invalid YAML: #{ex.message}")
      end

      private def self.walk(node : YAML::Any, prefix : String?, result : Hash(String, String)) : Nil
        if hash = node.as_h?
          hash.each do |key, value|
            key_name = key.as_s? || key.to_s
            walk(value, prefix ? "#{prefix}.#{key_name}" : key_name, result)
          end
          return
        end

        return unless prefix
        result[prefix] = scalar(node)
      end

      private def self.scalar(node : YAML::Any) : String
        if array = node.as_a?
          return "[#{array.map { |item| scalar(item) }.join(", ")}]"
        end

        raw = node.raw
        return "null" if raw.nil?
        raw.to_s
      end
    end
  end
end
