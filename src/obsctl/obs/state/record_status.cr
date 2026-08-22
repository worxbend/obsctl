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
        bytes : Int64? = nil
    end
  end
end
