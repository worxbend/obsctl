require "yaml"
require "../domain/errors"

module Obsctl
  module Config
    record ReconnectConfig,
      enabled : Bool = true,
      initial_delay_ms : Int32 = 500,
      max_delay_ms : Int32 = 5000,
      multiplier : Float64 = 1.8

    record ConnectionConfig,
      host : String = "127.0.0.1",
      port : Int32 = 4455,
      password_env : String? = "OBS_WEBSOCKET_PASSWORD",
      password : String? = nil,
      connect_timeout_ms : Int32 = 3000,
      request_timeout_ms : Int32 = 2500,
      reconnect : ReconnectConfig = ReconnectConfig.new

    record UiConfig,
      refresh_interval_ms : Int32 = 250,
      command_palette_prefix : String = "/",
      show_icons : Bool = true,
      theme : String = "default"

    record SceneConfig,
      name : String,
      alias : String? = nil,
      shortcut : String? = nil,
      group : String? = nil,
      stale : Bool = false

    record AudioInputConfig,
      name : String,
      alias : String? = nil,
      shortcut : String? = nil,
      kind : String = "input",
      stale : Bool = false

    record AudioConfig, inputs : Array(AudioInputConfig) = [] of AudioInputConfig

    record KeymapConfig,
      quit : Array(String) = ["q", "ctrl+c"],
      command_palette : Array(String) = ["/", ":"],
      reload_config : Array(String) = ["r"],
      dump_config : Array(String) = ["D"]

    class Config
      ALLOWED_TOP_LEVEL_KEYS = Set{
        "version",
        "connection",
        "ui",
        "scenes",
        "audio",
        "keymap",
      }

      property version : Int32
      property connection : ConnectionConfig
      property ui : UiConfig
      property scenes : Array(SceneConfig)
      property audio : AudioConfig
      property keymap : KeymapConfig

      def initialize(
        @version : Int32 = 1,
        @connection : ConnectionConfig = ConnectionConfig.new,
        @ui : UiConfig = UiConfig.new,
        @scenes : Array(SceneConfig) = [] of SceneConfig,
        @audio : AudioConfig = AudioConfig.new,
        @keymap : KeymapConfig = KeymapConfig.new,
      )
      end

      def self.default : self
        new
      end

      def self.from_yaml(yaml : String) : self
        any = YAML.parse(yaml)
        root = any.as_h
        reject_unknown_top_level_keys!(root)
        connection = parse_connection(root["connection"]?)
        ui = parse_ui(root["ui"]?)
        scenes = parse_scenes(root["scenes"]?)
        audio = parse_audio(root["audio"]?)
        keymap = parse_keymap(root["keymap"]?)
        new(
          version: root["version"]?.try(&.as_i).try(&.to_i32) || 1,
          connection: connection,
          ui: ui,
          scenes: scenes,
          audio: audio,
          keymap: keymap
        )
      end

      def to_yaml(io : IO) : Nil
        YAML.build(io) do |yaml|
          yaml.mapping do
            yaml.scalar "version"; yaml.scalar @version
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
              yaml.scalar "reconnect"
              yaml.mapping do
                yaml.scalar "enabled"; yaml.scalar @connection.reconnect.enabled
                yaml.scalar "initial_delay_ms"; yaml.scalar @connection.reconnect.initial_delay_ms
                yaml.scalar "max_delay_ms"; yaml.scalar @connection.reconnect.max_delay_ms
                yaml.scalar "multiplier"; yaml.scalar @connection.reconnect.multiplier
              end
            end
            yaml.scalar "ui"
            yaml.mapping do
              yaml.scalar "refresh_interval_ms"; yaml.scalar @ui.refresh_interval_ms
              yaml.scalar "command_palette_prefix"; yaml.scalar @ui.command_palette_prefix
              yaml.scalar "show_icons"; yaml.scalar @ui.show_icons
              yaml.scalar "theme"; yaml.scalar @ui.theme
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
            yaml.scalar "keymap"
            yaml.mapping do
              write_string_array(yaml, "quit", @keymap.quit)
              write_string_array(yaml, "command_palette", @keymap.command_palette)
              write_string_array(yaml, "reload_config", @keymap.reload_config)
              write_string_array(yaml, "dump_config", @keymap.dump_config)
            end
          end
        end
      end

      def to_yaml : String
        String.build { |io| to_yaml(io) }
      end

      private def write_optional(yaml : YAML::Builder, key : String, value : String?) : Nil
        return unless value
        yaml.scalar key
        yaml.scalar value
      end

      private def write_string_array(yaml : YAML::Builder, key : String, values : Array(String)) : Nil
        yaml.scalar key
        yaml.sequence { values.each { |value| yaml.scalar value } }
      end

      private def self.parse_connection(value : YAML::Any?) : ConnectionConfig
        hash = value.try(&.as_h?) || {} of YAML::Any => YAML::Any
        reconnect_hash = hash["reconnect"]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
        reconnect = ReconnectConfig.new(
          enabled: bool(reconnect_hash, "enabled", true),
          initial_delay_ms: int(reconnect_hash, "initial_delay_ms", 500),
          max_delay_ms: int(reconnect_hash, "max_delay_ms", 5000),
          multiplier: float(reconnect_hash, "multiplier", 1.8)
        )
        ConnectionConfig.new(
          host: string(hash, "host", "127.0.0.1"),
          port: int(hash, "port", 4455),
          password_env: string_or_nil(hash, "password_env") || "OBS_WEBSOCKET_PASSWORD",
          password: string_or_nil(hash, "password"),
          connect_timeout_ms: int(hash, "connect_timeout_ms", 3000),
          request_timeout_ms: int(hash, "request_timeout_ms", 2500),
          reconnect: reconnect
        )
      end

      private def self.parse_ui(value : YAML::Any?) : UiConfig
        hash = value.try(&.as_h?) || {} of YAML::Any => YAML::Any
        UiConfig.new(
          refresh_interval_ms: int(hash, "refresh_interval_ms", 250),
          command_palette_prefix: string(hash, "command_palette_prefix", "/"),
          show_icons: bool(hash, "show_icons", true),
          theme: string(hash, "theme", "default")
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

      private def self.parse_keymap(value : YAML::Any?) : KeymapConfig
        hash = value.try(&.as_h?) || {} of YAML::Any => YAML::Any
        KeymapConfig.new(
          quit: string_array(hash["quit"]?, ["q", "ctrl+c"]),
          command_palette: string_array(hash["command_palette"]?, ["/", ":"]),
          reload_config: string_array(hash["reload_config"]?, ["r"]),
          dump_config: string_array(hash["dump_config"]?, ["D"])
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
        hash[YAML::Any.new(key)]?.try(&.as_s?)
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
        hash[YAML::Any.new(key)]?.try(&.as_bool) || fallback
      end

      private def self.string_array(value : YAML::Any?, fallback : Array(String)) : Array(String)
        value.try(&.as_a?).try(&.map(&.as_s)) || fallback
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
