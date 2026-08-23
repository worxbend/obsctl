module Obsctl
  module TUI
    # A named set of scenes the dashboard keeps out of its scene list.
    #
    # These are obsctl's own presets. They are not OBS profiles (the panel the
    # dashboard shows as "Profiles", switched with SET_PROFILE) and not OBS
    # scene collections. Nothing here reaches OBS or the daemon: the daemon
    # keeps reporting every scene and the dashboard decides which of them it
    # draws, which is why hiding a scene needs no protocol change and takes
    # effect without a round trip.
    record ScenePreset, name : String, hidden_scenes : Set(String)

    # Every preset the dashboard knows about, plus which one is in effect.
    #
    # Deliberately free of any `config` dependency so `model.cr` can require it
    # without dragging the config layer into the model. Translating to and from
    # the on-disk shape is `ScenePresetPersistence`'s job.
    #
    # Every operation returns a new value instead of mutating, so applying an
    # edit is one assignment on the model.
    struct ScenePresets
      getter presets : Array(ScenePreset)
      # The preset in effect, or nil for "filter nothing here".
      getter active : String?

      def self.empty : self
        new
      end

      def initialize(@presets = [] of ScenePreset, @active = nil)
      end

      # nil when nothing is active, and also when `active` names a preset that
      # is not in the list: a hand-edited config file has to degrade to "every
      # scene visible" rather than to an empty scene list.
      def active_preset : ScenePreset?
        name = @active
        return unless name
        @presets.find { |preset| preset.name == name }
      end

      # The scene names the active preset hides, empty when none is active.
      def hidden_names : Set(String)
        active_preset.try(&.hidden_scenes) || Set(String).new
      end

      def index_of(name : String) : Int32?
        @presets.index { |preset| preset.name == name }
      end

      # Replaces the preset with this name, or appends it when it is new, so
      # "save" is one operation whether the user is editing or creating.
      def upsert(name : String, hidden_scenes : Set(String)) : self
        preset = ScenePreset.new(name, hidden_scenes.dup)
        updated = @presets.dup
        if index = index_of(name)
          updated[index] = preset
        else
          updated << preset
        end
        ScenePresets.new(updated, @active)
      end

      def activate(name : String?) : self
        ScenePresets.new(@presets, name)
      end
    end
  end
end
