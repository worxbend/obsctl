module Obsctl
  module OBS
    module State
      # Full record output status from OBS `GetRecordStatus`.
      #
      # Every field is nilable: older obs-websocket builds omit some of them,
      # and the CLI renders a missing value as unknown rather than inventing
      # one. Duration and bytes are only meaningful while recording is active.
      record RecordStatus,
        active : Bool? = nil,
        paused : Bool? = nil,
        timecode : String? = nil,
        duration_ms : Int64? = nil,
        bytes : Int64? = nil do
        # Collapses `active` and `paused` into the one word that describes the
        # recording: "active", "paused", or "stopped".
        #
        # Three states, not two. OBS reports `active` and `paused`
        # independently, and a daemon that has not heard from OBS yet knows
        # neither -- so the caller supplies the word for that third case rather
        # than this claiming "stopped". The two callers word it differently and
        # both wordings are frozen output: the daemon writes "state unknown"
        # inside its one-line message, the CLI prints a dash.
        def state(unknown : String) : String
          case active
          when true  then paused == true ? "paused" : "active"
          when false then "stopped"
          else            unknown
          end
        end
      end
    end
  end
end
