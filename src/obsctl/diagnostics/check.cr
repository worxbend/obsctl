require "json"
require "../json_value"

module Obsctl
  module Diagnostics
    # Severity of a single doctor check.
    #
    # `Warn` deliberately does not fail the command: a warning describes a
    # setup that works but is worth changing (a plaintext password, a daemon
    # that is not installed as a service). Only `Fail` means obsctl cannot do
    # what the user is asking for.
    enum Status
      Ok
      Warn
      Fail

      def label : String
        case self
        in .ok?   then "ok"
        in .warn? then "warn"
        in .fail? then "fail"
        end
      end
    end

    # One diagnostic result.
    #
    # `remedy` is the whole point of the command: a check that reports a
    # problem without saying what to do about it just moves the user to a
    # search engine.
    record Check,
      name : String,
      status : Status,
      detail : String,
      remedy : String? = nil do
      def self.ok(name : String, detail : String) : self
        new(name, Status::Ok, detail)
      end

      def self.warn(name : String, detail : String, remedy : String? = nil) : self
        new(name, Status::Warn, detail, remedy)
      end

      def self.fail(name : String, detail : String, remedy : String? = nil) : self
        new(name, Status::Fail, detail, remedy)
      end

      # One shape, two serializers: the doctor's JSON envelope carries these
      # as JSON::Any built by `to_json_any`, and `to_json` delegates so the
      # two can never drift apart.
      def to_json(json : JSON::Builder) : Nil
        to_json_any.to_json(json)
      end

      def to_json_any : JSON::Any
        JsonValue.any({
          "name"   => name,
          "status" => status.label,
          "detail" => detail,
          "remedy" => remedy,
        })
      end
    end
  end
end
