require "json"

module Obsctl
  module Support
    def self.string_or_nil(object : JSON::Any, key : String) : String?
      value = object.as_h[key]?
      value.try(&.as_s?)
    end

    def self.bool_or_nil(object : JSON::Any, key : String) : Bool?
      value = object.as_h[key]?
      value.try(&.as_bool?)
    end

    def self.float_or_nil(object : JSON::Any, key : String) : Float64?
      value = object.as_h[key]?
      return nil unless value
      value.as_f? || value.as_i?.try(&.to_f64)
    end
  end
end
