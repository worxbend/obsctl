require "json"

module Obsctl
  module OBS
    module Requests
      module Audio
        GET_INPUT_LIST    = "GetInputList"
        GET_INPUT_MUTE    = "GetInputMute"
        SET_INPUT_MUTE    = "SetInputMute"
        TOGGLE_INPUT_MUTE = "ToggleInputMute"
        GET_INPUT_VOLUME  = "GetInputVolume"
        SET_INPUT_VOLUME  = "SetInputVolume"

        def self.input_name(name : String) : JSON::Any
          JSON.parse({"inputName" => name}.to_json)
        end

        def self.set_mute(name : String, muted : Bool) : JSON::Any
          JSON.parse({"inputName" => name, "inputMuted" => muted}.to_json)
        end

        def self.set_volume(name : String, multiplier : Float64) : JSON::Any
          JSON.parse({"inputName" => name, "inputVolumeMul" => multiplier}.to_json)
        end
      end
    end
  end
end
