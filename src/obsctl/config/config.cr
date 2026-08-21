require "yaml"
require "../domain/errors"
require "./config_value"

module Obsctl
  module Config
    # Reconnect policy loaded from the top-level `reconnect` config section.
    struct ReconnectConfig
      config_value(
        enabled : Bool = true,
        endless : Bool = true,
        initial_delay_ms : Int32 = 500,
        max_delay_ms : Int32 = 10_000,
        multiplier : Float64 = 1.8,
        jitter_ms : Int32 = 250,
      )

      # Raises `Domain::ConfigInvalid` when the backoff numbers cannot describe
      # a usable retry schedule.
      #
      # Lives here rather than in `ConfigSchema` so that adding a field to this
      # struct puts its rule in view; `ConfigSchema` is still the entry point
      # that decides when validation runs.
      def validate! : Nil
        if initial_delay_ms < 0
          raise Domain::ConfigInvalid.new("reconnect.initial_delay_ms cannot be negative")
        end
        if max_delay_ms < 0
          raise Domain::ConfigInvalid.new("reconnect.max_delay_ms cannot be negative")
        end
        if max_delay_ms < initial_delay_ms
          raise Domain::ConfigInvalid.new("reconnect.max_delay_ms must be greater than or equal to initial_delay_ms")
        end
        if multiplier < 1.0
          raise Domain::ConfigInvalid.new("reconnect.multiplier must be at least 1.0")
        end
        if jitter_ms < 0
          raise Domain::ConfigInvalid.new("reconnect.jitter_ms cannot be negative")
        end
      end
    end

    # Local daemon options that affect server IPC and lifecycle behavior.
    struct ServerConfig
      config_value(
        socket_path : String? = nil,
        pid_file : String? = nil,
        allow_remote_shutdown : Bool = false,
        start_embedded_if_missing : Bool = true,
      )
    end

    # obs-websocket connection settings read only by server or embedded clients.
    struct ConnectionConfig
      DEFAULT_PASSWORD_ENV = "OBS_WEBSOCKET_PASSWORD"

      config_value(
        host : String = "127.0.0.1",
        port : Int32 = 4455,
        # Three states, not two: absent means "use the conventional variable",
        # while a present-but-empty value means "there is no env password".
        password_env : String? = DEFAULT_PASSWORD_ENV,
        password : String? = nil,
        connect_timeout_ms : Int32 = 3000,
        request_timeout_ms : Int32 = 2500,
        # Legacy home of the reconnect policy, promoted by `Config`.
        reconnect : ReconnectConfig? = nil,
      )

      def after_initialize : Nil
        # `password_env:` with no value parses as nil; the config model spells
        # that "no environment password" as the empty string.
        @password_env = "" if @password_env.nil?
      end

      # Raises `Domain::ConfigInvalid` when the endpoint could not be dialed.
      def validate! : Nil
        raise Domain::ConfigInvalid.new("host cannot be empty") if host.blank?
        unless 1 <= port <= 65_535
          raise Domain::ConfigInvalid.new("port must be from 1 to 65535")
        end
      end
    end

    # User configuration for one OBS scene and its local aliases.
    struct SceneConfig
      config_value(
        name : String,
        alias : String? = nil,
        shortcut : String? = nil,
        group : String? = nil,
        stale : Bool = false,
        hidden : Bool = false,
      )
    end

    # User configuration for one OBS audio input and its local aliases.
    struct AudioInputConfig
      config_value(
        name : String,
        alias : String? = nil,
        shortcut : String? = nil,
        kind : String = "input",
        stale : Bool = false,
      )
    end

    # Collection of configured OBS audio inputs.
    struct AudioConfig
      config_value(inputs : Array(AudioInputConfig) = [] of AudioInputConfig)
    end

    # Optional overrides for any subset of the semantic color palette.
    struct CustomThemeConfig
      config_value(
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
        highlight_fg : String? = nil,
      )
    end

    # Dashboard appearance and behavior.
    struct UiConfig
      config_value(
        refresh_interval_ms : Int32 = 250,
        command_palette_prefix : String = "/",
        advanced_ui : Bool = true,
        show_icons : Bool = true,
        theme : String = "default",
        custom_theme : CustomThemeConfig? = nil,
        locale : String? = nil,
      )

      # Raises `Domain::ConfigInvalid` when a dashboard setting would leave the
      # UI unable to run: a non-positive refresh interval, or an empty palette
      # prefix that no keystroke could ever match.
      def validate! : Nil
        raise Domain::ConfigInvalid.new("ui.refresh_interval_ms must be positive") unless refresh_interval_ms > 0
        raise Domain::ConfigInvalid.new("ui.command_palette_prefix cannot be empty") if command_palette_prefix.empty?
      end
    end

    # Dashboard key bindings.
    #
    # Part of the on-disk schema so a config written by the Rust reference
    # loads here unchanged and survives a rewrite. The dashboard still resolves
    # these four actions from its built-in bindings -- which are the defaults
    # below -- so overriding them does not yet change what the keys do.
    struct KeymapConfig
      config_value(
        quit : Array(String) = ["q", "ctrl+c"],
        command_palette : Array(String) = ["/", ":"],
        reload_config : Array(String) = ["r"],
        dump_config : Array(String) = ["D"],
      )
    end

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
        "keymap",
      }

      # The document exactly as it appears on disk.
      #
      # Kept separate from `Config` because the two differ in one place: on
      # disk `reconnect` may be absent, at which point the legacy
      # `connection.reconnect` supplies it, whereas `Config` always has one.
      private struct Document
        include YAML::Serializable

        getter version : Int32 = 1
        getter server : ServerConfig = ServerConfig.new
        getter connection : ConnectionConfig = ConnectionConfig.new
        getter reconnect : ReconnectConfig? = nil
        getter scenes : Array(SceneConfig) = [] of SceneConfig
        getter audio : AudioConfig = AudioConfig.new
        getter ui : UiConfig = UiConfig.new
        getter keymap : KeymapConfig = KeymapConfig.new
      end

      property version : Int32
      property server : ServerConfig
      property connection : ConnectionConfig
      property reconnect : ReconnectConfig
      property scenes : Array(SceneConfig)
      property audio : AudioConfig
      property ui : UiConfig
      property keymap : KeymapConfig

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
        @keymap : KeymapConfig = KeymapConfig.new,
      )
        if legacy_reconnect = @connection.reconnect
          @reconnect = legacy_reconnect
        end
      end

      # Returns the built-in default configuration used by `obsctl init`.
      def self.default : self
        new
      end

      # Adopts every setting from another config, in place.
      #
      # The daemon hands one `Config` instance to the supervisor, the command
      # executor and the live OBS client at startup, and they all keep their
      # own reference to it. Rebinding a variable to a freshly loaded config
      # therefore only updates whichever component did the rebinding, leaving
      # the others reading settings from the old file. Copying the fields into
      # the shared instance is what makes `obsctl reload-config` visible
      # everywhere at once.
      #
      # Every field is listed deliberately: an omission here is silent, and
      # shows up as one part of the daemon disagreeing with another.
      #
      # Concurrency: this is shared mutable state with no lock, and readers run
      # on other fibers — the supervisor reads `reconnect` between attempts, the
      # command executor reads `scenes` while resolving an alias, the next OBS
      # connect reads `connection`. What makes that safe is that the assignments
      # below are plain field writes with no yield point between them, so under
      # Crystal's default single-threaded scheduler no fiber can be scheduled
      # partway through and observe a half-replaced config.
      #
      # That is a real dependency on the runtime, not a happy accident, so it is
      # written down here: **under `-Dpreview_mt` this method needs a lock and
      # readers need to take it too.** Do not add anything to the body that can
      # yield — an I/O call, a `sleep`, a channel operation — without adding
      # that lock first.
      def replace_with(other : self) : Nil
        @version = other.version
        @server = other.server
        @connection = other.connection
        @reconnect = other.reconnect
        @scenes = other.scenes
        @audio = other.audio
        @ui = other.ui
        @keymap = other.keymap
      end

      # Parses YAML into the typed config model and rejects unsupported top-level
      # keys so writes cannot silently discard user data.
      def self.from_yaml(yaml : String) : self
        reject_unknown_top_level_keys!(yaml)

        document = Document.from_yaml(yaml)
        new(
          version: document.version,
          server: document.server,
          # A top-level `reconnect` outranks the legacy nested one, so the
          # nested copy is dropped before `initialize` can promote it.
          connection: document.reconnect ? without_legacy_reconnect(document.connection) : document.connection,
          reconnect: document.reconnect || ReconnectConfig.new,
          scenes: document.scenes,
          audio: document.audio,
          ui: document.ui,
          keymap: document.keymap,
        )
      rescue ex : YAML::ParseException
        raise Domain::ConfigInvalid.new("invalid YAML: #{ex.message}")
      end

      private def self.without_legacy_reconnect(connection : ConnectionConfig) : ConnectionConfig
        ConnectionConfig.new(
          host: connection.host,
          port: connection.port,
          password_env: connection.password_env,
          password: connection.password,
          connect_timeout_ms: connection.connect_timeout_ms,
          request_timeout_ms: connection.request_timeout_ms,
          reconnect: nil,
        )
      end

      private def self.reject_unknown_top_level_keys!(yaml : String) : Nil
        root = YAML.parse(yaml).as_h?
        return unless root

        root.each_key do |key|
          field = key.as_s?
          unless field && ALLOWED_TOP_LEVEL_KEYS.includes?(field)
            raise Domain::ConfigInvalid.new("unsupported top-level config field: #{key}")
          end
        end
      end

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
          yaml.scalar "advanced_ui"; yaml.scalar @ui.advanced_ui
          yaml.scalar "show_icons"; yaml.scalar @ui.show_icons
          yaml.scalar "theme"; yaml.scalar @ui.theme
          if custom = @ui.custom_theme
            write_custom_theme(yaml, custom)
          end
          write_optional(yaml, "locale", @ui.locale)
        end
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
