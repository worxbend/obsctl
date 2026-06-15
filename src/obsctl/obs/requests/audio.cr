require "json"

module Obsctl
  module OBS
    module Requests
      # Request names and payload builders for OBS audio input operations.
      module Audio
        GET_INPUT_LIST    = "GetInputList"
        GET_INPUT_MUTE    = "GetInputMute"
        SET_INPUT_MUTE    = "SetInputMute"
        TOGGLE_INPUT_MUTE = "ToggleInputMute"
        GET_INPUT_VOLUME  = "GetInputVolume"
        SET_INPUT_VOLUME  = "SetInputVolume"

        # Builds payload for requests that target one input by OBS name.
        def self.input_name(name : String) : JSON::Any
          JSON.parse({"inputName" => name}.to_json)
        end

        # Builds payload for SetInputMute.
        def self.set_mute(name : String, muted : Bool) : JSON::Any
          JSON.parse({"inputName" => name, "inputMuted" => muted}.to_json)
        end

        # Builds payload for SetInputVolume using obs-websocket multiplier units.
        def self.set_volume(name : String, multiplier : Float64) : JSON::Any
          JSON.parse({"inputName" => name, "inputVolumeMul" => multiplier}.to_json)
        end
      end
    end
  end
end
