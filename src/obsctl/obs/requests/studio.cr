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
          JSON::Any.new({"profileName" => JSON::Any.new(name)} of String => JSON::Any)
        end

        def self.scene_collection(name : String) : JSON::Any
          JSON::Any.new({"sceneCollectionName" => JSON::Any.new(name)} of String => JSON::Any)
        end
      end
    end
  end
end
