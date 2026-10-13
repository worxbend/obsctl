require "./config"

# Canonical YAML serialization for `Config`, split out from the config model.
#
# This file owns the serialization *format* -- the fixed key order and the
# omit-when-off rules -- while `config_writer.cr` owns getting the resulting
# bytes onto disk atomically. Reopening the class keeps `to_yaml` an ordinary
# method on `Config`, reachable from every file that requires `./config`.
module Obsctl
  module Config
    class Config
      # Writes the config in the canonical schema, including top-level
      # `server` and `reconnect` sections.
      #
      # Written by hand rather than derived from the field declarations because
      # this is the on-disk format `obsctl config migrate` converges a file
      # towards: key order is fixed, `socket_path` and `pid_file` are emitted
      # even when empty so the keys are discoverable, and flags that are off
      # are left out. Those are format decisions, not serializer defaults.
      def to_yaml(io : IO) : Nil
        YAML.build(io) do |yaml|
          yaml.mapping do
            yaml.scalar "version"; yaml.scalar @version
            write_server(yaml)
            write_connection(yaml)
            write_reconnect(yaml)
            write_scenes(yaml)
            write_scene_profiles(yaml)
            write_audio(yaml)
            write_ui(yaml)
            write_keymap(yaml)
          end
        end
      end

      private def write_server(yaml : YAML::Builder) : Nil
        yaml.scalar "server"
        yaml.mapping do
          yaml.scalar "socket_path"; write_nullable_string(yaml, @server.socket_path)
          yaml.scalar "pid_file"; write_nullable_string(yaml, @server.pid_file)
          yaml.scalar "allow_remote_shutdown"; yaml.scalar @server.allow_remote_shutdown
          yaml.scalar "start_embedded_if_missing"; yaml.scalar @server.start_embedded_if_missing
        end
      end

      private def write_connection(yaml : YAML::Builder) : Nil
        yaml.scalar "connection"
        yaml.mapping do
          yaml.scalar "host"; yaml.scalar @connection.host
          yaml.scalar "port"; yaml.scalar @connection.port
          if password_env = @connection.password_env
            yaml.scalar "password_env"; yaml.scalar password_env
          end
          if password = @connection.password
            yaml.scalar "password"; yaml.scalar password
          end
          yaml.scalar "connect_timeout_ms"; yaml.scalar @connection.connect_timeout_ms
          yaml.scalar "request_timeout_ms"; yaml.scalar @connection.request_timeout_ms
        end
      end

      private def write_reconnect(yaml : YAML::Builder) : Nil
        yaml.scalar "reconnect"
        yaml.mapping do
          yaml.scalar "enabled"; yaml.scalar @reconnect.enabled
          yaml.scalar "endless"; yaml.scalar @reconnect.endless
          yaml.scalar "initial_delay_ms"; yaml.scalar @reconnect.initial_delay_ms
          yaml.scalar "max_delay_ms"; yaml.scalar @reconnect.max_delay_ms
          yaml.scalar "multiplier"; yaml.scalar @reconnect.multiplier
          yaml.scalar "jitter_ms"; yaml.scalar @reconnect.jitter_ms
        end
      end

      private def write_scenes(yaml : YAML::Builder) : Nil
        yaml.scalar "scenes"
        yaml.sequence do
          @scenes.each do |scene|
            yaml.mapping do
              yaml.scalar "name"; yaml.scalar scene.name
              write_optional(yaml, "alias", scene.alias)
              write_optional(yaml, "shortcut", scene.shortcut)
              write_optional(yaml, "group", scene.group)
              if scene.stale
                yaml.scalar "stale"; yaml.scalar true
              end
              if scene.hidden
                yaml.scalar "hidden"; yaml.scalar true
              end
            end
          end
        end
      end

      private def write_audio(yaml : YAML::Builder) : Nil
        yaml.scalar "audio"
        yaml.mapping do
          yaml.scalar "inputs"
          yaml.sequence do
            @audio.inputs.each do |input|
              yaml.mapping do
                yaml.scalar "name"; yaml.scalar input.name
                write_optional(yaml, "alias", input.alias)
                write_optional(yaml, "shortcut", input.shortcut)
                yaml.scalar "kind"; yaml.scalar input.kind
                if input.stale
                  yaml.scalar "stale"; yaml.scalar true
                end
              end
            end
          end
        end
      end

      private def write_ui(yaml : YAML::Builder) : Nil
        yaml.scalar "ui"
        yaml.mapping do
          yaml.scalar "refresh_interval_ms"; yaml.scalar @ui.refresh_interval_ms
          yaml.scalar "command_palette_prefix"; yaml.scalar @ui.command_palette_prefix
          yaml.scalar "mouse"; yaml.scalar @ui.mouse
          yaml.scalar "advanced_ui"; yaml.scalar @ui.advanced_ui
          yaml.scalar "show_icons"; yaml.scalar @ui.show_icons
          yaml.scalar "theme"; yaml.scalar @ui.theme
          if custom = @ui.custom_theme
            write_custom_theme(yaml, custom)
          end
          write_optional(yaml, "locale", @ui.locale)
        end
      end

      # Written straight after `scenes:`, because that is the list these
      # describe -- the same order obsctl-rs emits them in, so a file written by
      # either implementation round-trips through the other unchanged.
      #
      # Omitted entirely while there is nothing to say, so a config file that
      # never used scene profiles is rewritten exactly as it was and `config
      # migrate` reports no change for it. Same rule `custom_theme` and the
      # per-scene `hidden` flag already follow. obsctl-rs instead always emits
      # `scene_profiles: []` and `active_scene_profile: null`; both sides
      # default the keys to empty when reading, so the two agree on meaning and
      # differ only in whether they spell the default out.
      private def write_scene_profiles(yaml : YAML::Builder) : Nil
        return if @scene_profiles.empty? && @active_scene_profile.nil?

        yaml.scalar "scene_profiles"
        yaml.sequence do
          @scene_profiles.each do |profile|
            yaml.mapping do
              yaml.scalar "name"; yaml.scalar profile.name
              # Written even when empty: an empty list is the meaningful
              # statement "this profile hides nothing", not an absent setting.
              yaml.scalar "hidden"
              yaml.sequence { profile.hidden.each { |name| yaml.scalar name } }
            end
          end
        end
        write_optional(yaml, "active_scene_profile", @active_scene_profile)
      end

      private def write_custom_theme(yaml : YAML::Builder, custom : CustomThemeConfig) : Nil
        yaml.scalar "custom_theme"
        yaml.mapping do
          write_optional(yaml, "bg", custom.bg)
          write_optional(yaml, "accent", custom.accent)
          write_optional(yaml, "accent_alt", custom.accent_alt)
          write_optional(yaml, "fg", custom.fg)
          write_optional(yaml, "muted", custom.muted)
          write_optional(yaml, "border", custom.border)
          write_optional(yaml, "border_focus", custom.border_focus)
          write_optional(yaml, "success", custom.success)
          write_optional(yaml, "warning", custom.warning)
          write_optional(yaml, "danger", custom.danger)
          write_optional(yaml, "info", custom.info)
          write_optional(yaml, "highlight_bg", custom.highlight_bg)
          write_optional(yaml, "highlight_fg", custom.highlight_fg)
        end
      end

      private def write_keymap(yaml : YAML::Builder) : Nil
        yaml.scalar "keymap"
        yaml.mapping do
          write_keys(yaml, "quit", @keymap.quit)
          write_keys(yaml, "command_palette", @keymap.command_palette)
          write_keys(yaml, "reload_config", @keymap.reload_config)
          write_keys(yaml, "dump_config", @keymap.dump_config)
        end
      end

      # Serializes the config to canonical YAML.
      def to_yaml : String
        String.build { |io| to_yaml(io) }
      end

      private def write_keys(yaml : YAML::Builder, key : String, keys : Array(String)) : Nil
        yaml.scalar key
        yaml.sequence { keys.each { |binding| yaml.scalar binding } }
      end

      private def write_optional(yaml : YAML::Builder, key : String, value : String?) : Nil
        return unless value
        yaml.scalar key
        yaml.scalar value
      end

      private def write_nullable_string(yaml : YAML::Builder, value : String?) : Nil
        if value
          yaml.scalar value
        else
          yaml.scalar nil
        end
      end
    end
  end
end
