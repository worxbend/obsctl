module Obsctl
  module OBS
    module Protocol
      module EventSubscription
        NONE         = 0
        GENERAL      = 1 << 0
        CONFIG       = 1 << 1
        SCENES       = 1 << 2
        INPUTS       = 1 << 3
        TRANSITIONS  = 1 << 4
        FILTERS      = 1 << 5
        OUTPUTS      = 1 << 6
        SCENE_ITEMS  = 1 << 7
        MEDIA_INPUTS = 1 << 8
        VENDORS      = 1 << 9
        UI           = 1 << 10
        CANVASES     = 1 << 11

        INPUT_VOLUME_METERS          = 1 << 16
        INPUT_ACTIVE_STATE_CHANGED   = 1 << 17
        INPUT_SHOW_STATE_CHANGED     = 1 << 18
        SCENE_ITEM_TRANSFORM_CHANGED = 1 << 19

        ALL =
          GENERAL |
            CONFIG |
            SCENES |
            INPUTS |
            TRANSITIONS |
            FILTERS |
            OUTPUTS |
            SCENE_ITEMS |
            MEDIA_INPUTS |
            VENDORS |
            UI |
            CANVASES

        SERVER_DEFAULT = GENERAL | SCENES | INPUTS
      end
    end
  end
end
