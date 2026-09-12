require "json"

module Obsctl
  module OBS
    module Requests
      # Request names and payload builders for OBS scene operations.
      module Scenes
        GET_SCENE_LIST            = "GetSceneList"
        GET_CURRENT_PROGRAM_SCENE = "GetCurrentProgramScene"
        SET_CURRENT_PROGRAM_SCENE = "SetCurrentProgramScene"

        # Builds payload for SetCurrentProgramScene.
        def self.set_current_program_scene(name : String) : JSON::Any
          JSON::Any.new({"sceneName" => JSON::Any.new(name)} of String => JSON::Any)
        end
      end
    end
  end
end
