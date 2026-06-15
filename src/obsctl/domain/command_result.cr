module Obsctl
  module Domain
    record CommandResult, ok : Bool, message : String do
      def self.ok(message : String) : self
        new(true, message)
      end

      def self.failed(message : String) : self
        new(false, message)
      end
    end
  end
end
