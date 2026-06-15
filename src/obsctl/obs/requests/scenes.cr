require "json"

module Obsctl
  module OBS
    module Requests
      module Scenes
        GET_SCENE_LIST            = "GetSceneList"
        GET_CURRENT_PROGRAM_SCENE = "GetCurrentProgramScene"
        SET_CURRENT_PROGRAM_SCENE = "SetCurrentProgramScene"

        def self.set_current_program_scene(name : String) : JSON::Any
          JSON.parse({"sceneName" => name}.to_json)
        end
      end
    end
  end
end
