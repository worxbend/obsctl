require "./scene_state"
require "./audio_state"
require "./output_state"

module Obsctl
  module OBS
    module State
      record ObsSnapshot,
        connected : Bool,
        obs_studio_version : String?,
        obs_websocket_version : String?,
        current_scene : String?,
        scenes : Array(SceneState),
        audio_inputs : Array(AudioState),
        output : OutputState = OutputState.new,
        last_error : String? = nil,
        updated_at : Time = Time.utc
    end
  end
end
