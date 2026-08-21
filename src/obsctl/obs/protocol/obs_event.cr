require "json"
require "./event"
require "./json_value"

module Obsctl
  module OBS
    module Protocol
      # An obs-websocket event, translated into terms the daemon uses.
      #
      # This is the anticorruption layer for the OBS event stream. Everything
      # peculiar to the vendor protocol lives here and nowhere else: the event
      # type spellings, the camelCase payload keys, the fact that OBS reports a
      # volume multiplier as a JSON float in some builds and a JSON integer in
      # others, and the decision that an event missing the field it exists to
      # carry is not worth acting on.
      #
      # Before this existed, `ObsSupervisor#apply_event` did all of that inline,
      # which meant the daemon's supervision logic changed whenever OBS changed
      # its wire format. Now the supervisor folds typed values into state and
      # never sees a `JSON::Any`.
      abstract struct ObsEvent
        # The program scene changed to `scene_name`.
        struct ProgramSceneChanged < ObsEvent
          getter scene_name : String

          def initialize(@scene_name : String)
          end
        end

        # One input's mute state changed.
        struct InputMuteChanged < ObsEvent
          getter input_name : String
          getter muted : Bool

          def initialize(@input_name : String, @muted : Bool)
          end
        end

        # One input's volume changed. Either level may be absent; OBS does not
        # always send both, and nil means "unchanged as far as this event says".
        struct InputVolumeChanged < ObsEvent
          getter input_name : String
          getter volume_mul : Float64?
          getter volume_db : Float64?

          def initialize(@input_name : String, @volume_mul : Float64?, @volume_db : Float64?)
          end
        end

        # The set of scenes changed in a way that needs a re-read: created,
        # removed, renamed, or reordered. OBS spells these four different ways;
        # the daemon's response to all of them is the same.
        struct SceneListChanged < ObsEvent
        end

        # The set of inputs changed and needs a re-read.
        struct InputListChanged < ObsEvent
        end

        # The stream output started or stopped.
        struct StreamStateChanged < ObsEvent
          getter active : Bool

          def initialize(@active : Bool)
          end
        end

        # The record output started or stopped.
        struct RecordStateChanged < ObsEvent
          getter active : Bool

          def initialize(@active : Bool)
          end
        end

        # The active profile or scene collection changed. Both replace enough
        # of OBS's state that only a full snapshot is trustworthy afterwards.
        struct StudioContextChanged < ObsEvent
        end

        # Translates a raw event, or returns nil.
        #
        # Nil means "nothing for the daemon to do": either the event type is one
        # obsctl does not track, or it is one it does track but arrived without
        # the field it exists to carry. Both are non-events, and neither is
        # worth failing a connection over.
        def self.from(event : Event) : ObsEvent?
          data = event.event_data

          case event.event_type
          when "CurrentProgramSceneChanged"
            string(data, "sceneName").try { |name| ProgramSceneChanged.new(name) }
          when "InputMuteStateChanged"
            name = string(data, "inputName")
            muted = boolean(data, "inputMuted")
            InputMuteChanged.new(name, muted) if name && !muted.nil?
          when "InputVolumeChanged"
            string(data, "inputName").try do |name|
              InputVolumeChanged.new(name, number(data, "inputVolumeMul"), number(data, "inputVolumeDb"))
            end
          when "SceneListChanged", "SceneCreated", "SceneRemoved", "SceneNameChanged"
            SceneListChanged.new
          when "InputCreated", "InputRemoved", "InputNameChanged"
            InputListChanged.new
          when "StreamStateChanged"
            boolean(data, "outputActive").try { |active| StreamStateChanged.new(active) }
          when "RecordStateChanged"
            boolean(data, "outputActive").try { |active| RecordStateChanged.new(active) }
          when "CurrentProfileChanged", "ProfileListChanged",
               "CurrentSceneCollectionChanged", "SceneCollectionListChanged"
            StudioContextChanged.new
          end
        end

        private def self.string(data : JSON::Any?, key : String) : String?
          JsonValue.string(data, key)
        end

        private def self.boolean(data : JSON::Any?, key : String) : Bool?
          JsonValue.boolean(data, key)
        end

        private def self.number(data : JSON::Any?, key : String) : Float64?
          JsonValue.number(data, key)
        end
      end
    end
  end
end
