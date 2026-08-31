require "yaml"
require "../domain/errors"
require "../domain/scene_profiles"
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

    # One named set of scene-visibility choices -- an "obsctl scene profile",
    # unrelated to an OBS profile and to an OBS scene collection (both of which
    # the dashboard shows in panels of their own).
    #
    # `hidden` names the scenes this profile hides, spelled as OBS spells them;
    # every other scene is visible while it is active. Nothing here is ever sent
    # to OBS -- the daemon resolves the list into a per-scene `hidden` flag and
    # every client reads that flag.
    struct SceneProfileConfig
      config_value(
        name : String,
        hidden : Array(String) = [] of String,
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
        getter scene_profiles : Array(SceneProfileConfig) = [] of SceneProfileConfig
        getter active_scene_profile : String? = nil
        getter audio : AudioConfig = AudioConfig.new
        getter ui : UiConfig = UiConfig.new
        getter keymap : KeymapConfig = KeymapConfig.new

        # The names of the fields above, read off the struct itself at compile
        # time rather than typed out again.
        #
        # These names are the YAML keys: `YAML::Serializable` maps a key to the
        # instance variable of the same name, none of the fields above renames
        # itself with `@[YAML::Field(key: ...)]`, and the struct does not
        # include `YAML::Serializable::Unmapped`, which would add an instance
        # variable that is no key at all. Doing either of those things breaks
        # the equivalence, so teach this method about it first.
        #
        # `instance_vars` is only readable from inside a method body, which is
        # why this is a method and not a constant; `@type` in a class method is
        # the metaclass, hence `.instance`.
        def self.field_names : Array(String)
          {% begin %}
            {{ @type.instance.instance_vars.map(&.name.stringify) }}
          {% end %}
        end
      end

      # The top-level keys a config file may contain, derived from the document
      # rather than typed out a second time.
      #
      # `reject_unknown_top_level_keys!` refuses a file carrying anything not in
      # here, so the two lists drifting apart fails in whichever direction the
      # drift went and neither way says so: a key added to `Document` but
      # forgotten here makes a perfectly valid file be rejected, while a key
      # here that `Document` does not read is accepted and then silently
      # dropped the next time the file is written back out. Deriving the set
      # means there is only one list to keep right.
      ALLOWED_TOP_LEVEL_KEYS = Set.new(Document.field_names)

      property version : Int32
      property server : ServerConfig
      property connection : ConnectionConfig
      property reconnect : ReconnectConfig
      property scenes : Array(SceneConfig)
      property scene_profiles : Array(SceneProfileConfig)
      property active_scene_profile : String?
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
        @scene_profiles : Array(SceneProfileConfig) = [] of SceneProfileConfig,
        @active_scene_profile : String? = nil,
        @audio : AudioConfig = AudioConfig.new,
        @ui : UiConfig = UiConfig.new,
        @keymap : KeymapConfig = KeymapConfig.new,
      )
        if legacy_reconnect = @connection.reconnect
          @reconnect = legacy_reconnect
        end
      end

      # The profile `active_scene_profile` names, matched the way names are
      # matched everywhere else -- trimmed and case-insensitively -- or `nil`
      # when nothing is active or the name answers to no saved profile.
      #
      # A name nothing answers to degrading to `nil` rather than raising is
      # deliberate: a hand-edited file has to fall back to the per-scene flags
      # rather than to an empty scene list. `ConfigSchema.warnings` reports it.
      def active_scene_profile_config : SceneProfileConfig?
        @scene_profiles.find do |profile|
          Domain::SceneProfileNames.same?(profile.name, @active_scene_profile)
        end
      end

      # The one answer to "is this scene hidden", resolved from this config.
      #
      # Every caller goes through here rather than reading `scenes[].hidden` or
      # a profile's list directly: two places deciding the same question is how
      # a dashboard ends up disagreeing with the daemon about what to draw.
      def scene_visibility : Domain::SceneVisibility
        Domain::SceneVisibility.resolve(
          @scenes.map { |scene| {scene.name, scene.hidden} },
          active_scene_profile_config.try(&.hidden)
        )
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
        @scene_profiles = other.scene_profiles
        @active_scene_profile = other.active_scene_profile
        @audio = other.audio
        @ui = other.ui
        @keymap = other.keymap
      end

      # A copy safe to edit, so an operation that fails partway leaves the
      # shared config object untouched.
      #
      # `replace_with` alone does not give that. It assigns every field by
      # reference, so a config built that way still shares `scenes`,
      # `scene_profiles`, `audio.inputs` and the keymap's key lists with the
      # live object the supervisor, the command executor and the OBS client are
      # all reading. Appending to any one of those would be visible daemon-wide
      # before a single byte reached disk. Each of those collections is
      # therefore given a copy of its own below.
      #
      # The copy is one level deep, which is what the callers need: an edit may
      # add, remove, reorder or wholesale-replace entries in these collections,
      # but must not reach inside an entry and mutate a collection the entry
      # itself holds -- a scene profile's `hidden` list being the only one.
      #
      # Named `copy` rather than `dup` deliberately: Crystal's `Object#dup` is
      # shallow by contract, and callers already rely on `Config#dup` being
      # exactly that.
      #
      # Every field carrying a collection is listed deliberately, for the same
      # reason `replace_with` lists every field: an omission here is silent.
      def copy : self
        copy = Config.new
        copy.replace_with(self)
        copy.scenes = @scenes.dup
        copy.scene_profiles = @scene_profiles.dup
        copy.audio = @audio.copy_with(inputs: @audio.inputs.dup)
        copy.keymap = @keymap.copy_with(
          quit: @keymap.quit.dup,
          command_palette: @keymap.command_palette.dup,
          reload_config: @keymap.reload_config.dup,
          dump_config: @keymap.dump_config.dup,
        )
        copy
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
          connection: document.reconnect ? document.connection.copy_with(reconnect: nil) : document.connection,
          reconnect: document.reconnect || ReconnectConfig.new,
          scenes: document.scenes,
          scene_profiles: document.scene_profiles,
          active_scene_profile: document.active_scene_profile,
          audio: document.audio,
          ui: document.ui,
          keymap: document.keymap,
        )
      rescue ex : YAML::ParseException
        raise Domain::ConfigInvalid.new("invalid YAML: #{ex.message}")
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
    end
  end
end

# The canonical YAML writer reopens `Config`; required here so every file
# that requires `./config` also sees `to_yaml`.
require "./config_canonical_yaml"
