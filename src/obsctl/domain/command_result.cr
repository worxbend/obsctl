module Obsctl
  module Domain
    # Text result returned by command handlers for display-oriented clients.
    record CommandResult, ok : Bool, message : String do
      # Builds a successful command result.
      def self.ok(message : String) : self
        new(true, message)
      end

      # Builds a failed command result.
      def self.failed(message : String) : self
        new(false, message)
      end
    end
  end
end
