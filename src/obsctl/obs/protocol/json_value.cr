require "json"

module Obsctl
  module OBS
    module Protocol
      # Reads one typed field out of an obs-websocket JSON body.
      #
      # obs-websocket is not strict about the JSON type it uses for a number:
      # it sends whole-number values as integers and everything else as
      # floats, so a volume reading of exactly 1 arrives with a different JSON
      # type than a reading of 0.5. Both are the same quantity, and every
      # place that reads an OBS number has to accept either. That rule used to
      # be rediscovered in each of the three files that decode OBS responses;
      # it lives here now.
      #
      # Every reader answers nil rather than raising when the field is absent
      # or is not the type asked for. A field OBS did not send is a fact about
      # this response, not a reason to fail the connection — callers decide
      # whether a missing value is a default, an omission, or an error.
      module JsonValue
        def self.string(data : JSON::Any?, key : String) : String?
          data.try(&.[key]?).try(&.as_s?)
        end

        def self.boolean(data : JSON::Any?, key : String) : Bool?
          data.try(&.[key]?).try(&.as_bool?)
        end

        # Accepts either JSON form of a number. See the note above.
        def self.number(data : JSON::Any?, key : String) : Float64?
          number(data.try(&.[key]?))
        end

        # The same rule for a value that has already been pulled out of its
        # object — an element of an array, or a field a caller chose between.
        def self.number(value : JSON::Any?) : Float64?
          value.try { |json| json.as_f? || json.as_i?.try(&.to_f64) }
        end

        def self.integer(data : JSON::Any?, key : String) : Int64?
          data.try(&.[key]?).try(&.as_i64?)
        end
      end
    end
  end
end
