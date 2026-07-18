require "json"

module Obsctl
  module OBS
    module Requests
      module Studio
        GET_PROFILE_LIST          = "GetProfileList"
        SET_CURRENT_PROFILE       = "SetCurrentProfile"
        GET_SCENE_COLLECTION_LIST = "GetSceneCollectionList"
        SET_SCENE_COLLECTION      = "SetCurrentSceneCollection"
        GET_STATS                 = "GetStats"

        def self.profile(name : String) : JSON::Any
          JSON.parse({"profileName" => name}.to_json)
        end

        def self.scene_collection(name : String) : JSON::Any
          JSON.parse({"sceneCollectionName" => name}.to_json)
        end
      end
    end
  end
end
