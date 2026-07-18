require "yaml"
require "../domain/errors"

module Obsctl
  module Config
    # Reconnect policy loaded from the top-level `reconnect` config section.
    record ReconnectConfig,
      enabled : Bool = true,
      endless : Bool = true,
      initial_delay_ms : Int32 = 500,
      max_delay_ms : Int32 = 10_000,
      multiplier : Float64 = 1.8,
      jitter_ms : Int32 = 250

    # Local daemon options that affect server IPC and lifecycle behavior.
    record ServerConfig,
      socket_path : String? = nil,
      pid_file : String? = nil,
      allow_remote_shutdown : Bool = false,
      start_embedded_if_missing : Bool = true

    # obs-websocket connection settings read only by server or embedded clients.
    record ConnectionConfig,
      host : String = "127.0.0.1",
      port : Int32 = 4455,
      password_env : String? = "OBS_WEBSOCKET_PASSWORD",
      password : String? = nil,
      connect_timeout_ms : Int32 = 3000,
      request_timeout_ms : Int32 = 2500,
      reconnect : ReconnectConfig? = nil

    # User configuration for one OBS scene and its local aliases.
    record SceneConfig,
      name : String,
      alias : String? = nil,
      shortcut : String? = nil,
      group : String? = nil,
      stale : Bool = false

    # User configuration for one OBS audio input and its local aliases.
    record AudioInputConfig,
      name : String,
      alias : String? = nil,
      shortcut : String? = nil,
      kind : String = "input",
      stale : Bool = false

    # Collection of configured OBS audio inputs.
    record AudioConfig, inputs : Array(AudioInputConfig) = [] of AudioInputConfig

    record CustomThemeConfig,
      bg : String? = nil,
      accent : String? = nil,
      accent_alt : String? = nil,
      fg : String? = nil,
      muted : String? = nil,
      border : String? = nil,
      border_focus : String? = nil,
      success : String? = nil,
      warning : String? = nil,
      danger : String? = nil,
      info : String? = nil,
      highlight_bg : String? = nil,
      highlight_fg : String? = nil

    record UiConfig,
      refresh_interval_ms : Int32 = 250,
      command_palette_prefix : String = "/",
      advanced_ui : Bool = true,
      show_icons : Bool = true,
      theme : String = "default",
      custom_theme : CustomThemeConfig? = nil,
      locale : String? = nil

    # Parsed obsctl configuration with canonical top-level server and reconnect sections.
    class Config
      ALLOWED_TOP_LEVEL_KEYS = Set{
        "version",
        "server",
        "connection",
        "reconnect",
        "scenes",
        "audio",
        "ui",
      }

      property version : Int32
      property server : ServerConfig
      property connection : ConnectionConfig
      property reconnect : ReconnectConfig
      property scenes : Array(SceneConfig)
      property audio : AudioConfig
      property ui : UiConfig

      # Builds a config object, migrating legacy `connection.reconnect` into the
      # canonical top-level `reconnect` field when present.
      def initialize(
        @version : Int32 = 1,
        @server : ServerConfig = ServerConfig.new,
        @connection : ConnectionConfig = ConnectionConfig.new,
        @reconnect : ReconnectConfig = ReconnectConfig.new,
        @scenes : Array(SceneConfig) = [] of SceneConfig,
        @audio : AudioConfig = AudioConfig.new,
        @ui : UiConfig = UiConfig.new,
      )
        if legacy_reconnect = @connection.reconnect
          @reconnect = legacy_reconnect
        end
      end

      # Returns the built-in default configuration used by `obsctl init`.
      def self.default : self
        new
      end

      # Parses YAML into the typed config model and rejects unsupported top-level
      # keys so writes cannot silently discard user data.
      def self.from_yaml(yaml : String) : self
        any = YAML.parse(yaml)
        root = any.as_h
        reject_unknown_top_level_keys!(root)
        server = parse_server(root["server"]?)
        connection = parse_connection(root["connection"]?, include_legacy_reconnect: false)
        reconnect = parse_reconnect(root["reconnect"]?, root["connection"]?)
        scenes = parse_scenes(root["scenes"]?)
        audio = parse_audio(root["audio"]?)
        ui = parse_ui(root["ui"]?)
        new(
          version: root["version"]?.try(&.as_i).try(&.to_i32) || 1,
          server: server,
          connection: connection,
          reconnect: reconnect,
          scenes: scenes,
          audio: audio,
          ui: ui,
        )
      end

      # Writes the config in the canonical schema, including top-level
      # `server` and `reconnect` sections.
      def to_yaml(io : IO) : Nil
        YAML.build(io) do |yaml|
          yaml.mapping do
            yaml.scalar "version"; yaml.scalar @version
            yaml.scalar "server"
            yaml.mapping do
              yaml.scalar "socket_path"; write_nullable_string(yaml, @server.socket_path)
              yaml.scalar "pid_file"; write_nullable_string(yaml, @server.pid_file)
              yaml.scalar "allow_remote_shutdown"; yaml.scalar @server.allow_remote_shutdown
              yaml.scalar "start_embedded_if_missing"; yaml.scalar @server.start_embedded_if_missing
            end
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
            yaml.scalar "reconnect"
            yaml.mapping do
              yaml.scalar "enabled"; yaml.scalar @reconnect.enabled
              yaml.scalar "endless"; yaml.scalar @reconnect.endless
              yaml.scalar "initial_delay_ms"; yaml.scalar @reconnect.initial_delay_ms
              yaml.scalar "max_delay_ms"; yaml.scalar @reconnect.max_delay_ms
              yaml.scalar "multiplier"; yaml.scalar @reconnect.multiplier
              yaml.scalar "jitter_ms"; yaml.scalar @reconnect.jitter_ms
            end
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
                end
              end
            end
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
            yaml.scalar "ui"
            yaml.mapping do
              yaml.scalar "refresh_interval_ms"; yaml.scalar @ui.refresh_interval_ms
              yaml.scalar "command_palette_prefix"; yaml.scalar @ui.command_palette_prefix
              yaml.scalar "advanced_ui"; yaml.scalar @ui.advanced_ui
              yaml.scalar "show_icons"; yaml.scalar @ui.show_icons
              yaml.scalar "theme"; yaml.scalar @ui.theme
              if custom = @ui.custom_theme
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
              write_optional(yaml, "locale", @ui.locale)
            end
          end
        end
      end

      # Serializes the config to canonical YAML.
      def to_yaml : String
        String.build { |io| to_yaml(io) }
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

      private def self.parse_connection(value : YAML::Any?, include_legacy_reconnect : Bool = true) : ConnectionConfig
        hash = value.try(&.as_h?) || {} of YAML::Any => YAML::Any
        ConnectionConfig.new(
          host: string(hash, "host", "127.0.0.1"),
          port: int(hash, "port", 4455),
          password_env: password_env(hash),
          password: string_or_nil(hash, "password"),
          connect_timeout_ms: int(hash, "connect_timeout_ms", 3000),
          request_timeout_ms: int(hash, "request_timeout_ms", 2500),
          reconnect: include_legacy_reconnect ? reconnect_from_connection(hash) : nil
        )
      end

      private def self.parse_server(value : YAML::Any?) : ServerConfig
        hash = value.try(&.as_h?) || {} of YAML::Any => YAML::Any
        ServerConfig.new(
          socket_path: string_or_nil(hash, "socket_path"),
          pid_file: string_or_nil(hash, "pid_file"),
          allow_remote_shutdown: bool(hash, "allow_remote_shutdown", false),
          start_embedded_if_missing: bool(hash, "start_embedded_if_missing", true)
        )
      end

      private def self.parse_reconnect(value : YAML::Any?, connection : YAML::Any?) : ReconnectConfig
        hash = value.try(&.as_h?)
        hash ||= connection.try(&.as_h?).try { |connection_hash| connection_hash["reconnect"]?.try(&.as_h?) }
        hash ||= {} of YAML::Any => YAML::Any
        ReconnectConfig.new(
          enabled: bool(hash, "enabled", true),
          endless: bool(hash, "endless", true),
          initial_delay_ms: int(hash, "initial_delay_ms", 500),
          max_delay_ms: int(hash, "max_delay_ms", 10_000),
          multiplier: float(hash, "multiplier", 1.8),
          jitter_ms: int(hash, "jitter_ms", 250)
        )
      end

      private def self.reconnect_from_connection(hash : Hash(YAML::Any, YAML::Any)) : ReconnectConfig?
        reconnect_hash = hash["reconnect"]?.try(&.as_h?)
        return nil unless reconnect_hash

        ReconnectConfig.new(
          enabled: bool(reconnect_hash, "enabled", true),
          endless: bool(reconnect_hash, "endless", true),
          initial_delay_ms: int(reconnect_hash, "initial_delay_ms", 500),
          max_delay_ms: int(reconnect_hash, "max_delay_ms", 10_000),
          multiplier: float(reconnect_hash, "multiplier", 1.8),
          jitter_ms: int(reconnect_hash, "jitter_ms", 250)
        )
      end

      private def self.parse_scenes(value : YAML::Any?) : Array(SceneConfig)
        array(value).map do |item|
          hash = item.as_h
          SceneConfig.new(
            name: required_string(hash, "name"),
            alias: string_or_nil(hash, "alias"),
            shortcut: string_or_nil(hash, "shortcut"),
            group: string_or_nil(hash, "group"),
            stale: bool(hash, "stale", false)
          )
        end
      end

      private def self.parse_audio(value : YAML::Any?) : AudioConfig
        hash = value.try(&.as_h?) || {} of YAML::Any => YAML::Any
        inputs = array(hash["inputs"]?).map do |item|
          input = item.as_h
          AudioInputConfig.new(
            name: required_string(input, "name"),
            alias: string_or_nil(input, "alias"),
            shortcut: string_or_nil(input, "shortcut"),
            kind: string(input, "kind", "input"),
            stale: bool(input, "stale", false)
          )
        end
        AudioConfig.new(inputs)
      end

      private def self.parse_ui(value : YAML::Any?) : UiConfig
        hash = value.try(&.as_h?) || {} of YAML::Any => YAML::Any
        UiConfig.new(
          refresh_interval_ms: int(hash, "refresh_interval_ms", 250),
          command_palette_prefix: string(hash, "command_palette_prefix", "/"),
          advanced_ui: bool(hash, "advanced_ui", true),
          show_icons: bool(hash, "show_icons", true),
          theme: string(hash, "theme", "default"),
          custom_theme: parse_custom_theme(hash["custom_theme"]?),
          locale: string_or_nil(hash, "locale")
        )
      end

      private def self.parse_custom_theme(value : YAML::Any?) : CustomThemeConfig?
        return nil unless value
        hash = value.as_h
        CustomThemeConfig.new(
          bg: string_or_nil(hash, "bg"), accent: string_or_nil(hash, "accent"),
          accent_alt: string_or_nil(hash, "accent_alt"), fg: string_or_nil(hash, "fg"),
          muted: string_or_nil(hash, "muted"), border: string_or_nil(hash, "border"),
          border_focus: string_or_nil(hash, "border_focus"), success: string_or_nil(hash, "success"),
          warning: string_or_nil(hash, "warning"), danger: string_or_nil(hash, "danger"),
          info: string_or_nil(hash, "info"), highlight_bg: string_or_nil(hash, "highlight_bg"),
          highlight_fg: string_or_nil(hash, "highlight_fg")
        )
      end

      private def self.array(value : YAML::Any?) : Array(YAML::Any)
        value.try(&.as_a?) || [] of YAML::Any
      end

      private def self.string(hash, key, fallback)
        string_or_nil(hash, key) || fallback
      end

      private def self.required_string(hash, key)
        string_or_nil(hash, key) || raise Domain::ConfigInvalid.new("missing required config field: #{key}")
      end

      private def self.string_or_nil(hash, key)
        value = hash[YAML::Any.new(key)]?
        return nil unless value

        value.as_s? || value.as_i?.try(&.to_s)
      end

      private def self.int(hash, key, fallback)
        hash[YAML::Any.new(key)]?.try(&.as_i).try(&.to_i32) || fallback
      end

      private def self.float(hash, key, fallback)
        value = hash[YAML::Any.new(key)]?
        return fallback unless value
        value.as_f? || value.as_i?.try(&.to_f64) || fallback
      end

      private def self.bool(hash, key, fallback)
        value = hash[YAML::Any.new(key)]?
        return fallback unless value

        parsed = value.as_bool?
        parsed.nil? ? fallback : parsed
      end

      private def self.password_env(hash) : String?
        key = YAML::Any.new("password_env")
        return "OBS_WEBSOCKET_PASSWORD" unless hash.has_key?(key)

        string_or_nil(hash, "password_env") || ""
      end

      private def self.reject_unknown_top_level_keys!(root : Hash(YAML::Any, YAML::Any)) : Nil
        root.each_key do |key|
          field = key.as_s?
          unless field && ALLOWED_TOP_LEVEL_KEYS.includes?(field)
            raise Domain::ConfigInvalid.new("unsupported top-level config field: #{key}")
          end
        end
      end
    end
  end
end
