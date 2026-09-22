require "./log_entry"

module Obsctl
  module TUI
    # The log pane's rolling window.
    #
    # The cap and the trim live with the entries rather than at the call
    # sites, so the bound holds by construction: a caller cannot append past
    # it, because there is no append but through `push`.
    class LogsPaneState
      MAX_LOG_ENTRIES = 200

      getter entries : Array(LogEntry)

      def initialize
        @entries = [] of LogEntry
      end

      def push(entry : LogEntry) : Nil
        @entries << entry
        @entries.shift(@entries.size - MAX_LOG_ENTRIES) if @entries.size > MAX_LOG_ENTRIES
      end
    end
  end
end
