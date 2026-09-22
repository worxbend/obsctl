require "../../runtime/logger"

module Obsctl
  module TUI
    record LogEntry,
      level : Runtime::LogLevel,
      message : String,
      code : String? = nil,
      timestamp : Time = Time.utc
  end
end
