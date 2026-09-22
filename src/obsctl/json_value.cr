require "json"

module Obsctl
  # Reads one typed field out of a JSON body.
  #
  # Lives outside the `obs/` layer because both sides of the wire use it: the
  # obs-websocket client decodes vendor responses with it, and the IPC codec
  # and dashboard decode daemon payloads with it — the leniency rules below
  # are not OBS-specific, they are how obsctl reads any JSON it did not write.
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

    # Builders for the other direction. The IPC response payload and the CLI
    # JSON envelopes speak JSON::Any, so a value that is already typed is
    # built straight into a JSON::Any tree here. The seam this replaces --
    # `JSON.parse(value.to_json)`, serialize and immediately parse back --
    # threw the typing away and paid serialize-plus-parse for every response
    # on the way out.
    def self.any(value : Nil) : JSON::Any
      JSON::Any.new(nil)
    end

    def self.any(value : Bool) : JSON::Any
      JSON::Any.new(value)
    end

    def self.any(value : String) : JSON::Any
      JSON::Any.new(value)
    end

    def self.any(value : Int) : JSON::Any
      JSON::Any.new(value.to_i64)
    end

    def self.any(value : Float) : JSON::Any
      JSON::Any.new(value.to_f64)
    end

    def self.any(value : Array(T)) : JSON::Any forall T
      JSON::Any.new(value.map { |item| any(item) })
    end

    def self.any(value : Hash(String, T)) : JSON::Any forall T
      JSON::Any.new(value.transform_values { |item| any(item) })
    end

    # Key order is insertion order in JSON::Any, and a named tuple keeps its
    # literal order -- which is what the golden fixtures pin, so the literal
    # here is the contract, not just a convenience.
    def self.any(value : NamedTuple) : JSON::Any
      JSON::Any.new(value.transform_values { |item| any(item) }.to_h)
    end

    def self.any(value : JSON::Any) : JSON::Any
      value
    end
  end
end
