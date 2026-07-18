require "./scene_state"
require "./audio_state"
require "./output_state"
require "./obs_stats"

module Obsctl
  module OBS
    module State
      # Authoritative OBS state snapshot distributed by the local server.
      record ObsSnapshot,
        connected : Bool,
        obs_studio_version : String?,
        obs_websocket_version : String?,
        current_scene : String?,
        scenes : Array(SceneState),
        audio_inputs : Array(AudioState),
        output : OutputState = OutputState.new,
        profiles : Array(String) = [] of String,
        current_profile : String? = nil,
        scene_collections : Array(String) = [] of String,
        current_scene_collection : String? = nil,
        stats : ObsStats? = nil,
        stream_bitrate_kbps : Float64? = nil,
        stream_duration_ms : Int64? = nil,
        record_duration_ms : Int64? = nil,
        last_error : String? = nil,
        updated_at : Time = Time.utc
    end
  end
end
