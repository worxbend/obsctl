module Obsctl
  module OBS
    module Protocol
      # obs-websocket event subscription bit masks.
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

        # Every category the daemon needs. obs-websocket only delivers an event
        # to clients subscribed to its category, so a missing bit here silently
        # turns the matching handler arm into dead code: `OUTPUTS` is what
        # carries `StreamStateChanged`, and without it a stream started from
        # the OBS UI or another client never reached daemon state.
        #
        # Two sets of consumers have to be represented, which is easy to forget
        # because only one of them lives in this process:
        #
        #   - `ObsSupervisor#apply_event`, which folds events into daemon state;
        #   - the dashboard, which reads the raw events fanned out over IPC.
        #     `INPUT_VOLUME_METERS` is here for it alone — the supervisor
        #     ignores that category, but without the bit the TUI's audio meters
        #     have no data to draw and sit at silence forever.
        #
        # `INPUT_VOLUME_METERS` is the one high-volume category included. OBS
        # emits it tens of times a second, which is the price of a live meter;
        # broadcasts to IPC clients are individually bounded, so a subscriber
        # that cannot keep up is dropped rather than slowing the daemon down.
        SERVER_DEFAULT = GENERAL | CONFIG | SCENES | INPUTS | OUTPUTS | INPUT_VOLUME_METERS
      end
    end
  end
end
