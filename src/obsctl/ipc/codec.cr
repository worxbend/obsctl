require "json"
require "../domain/errors"
require "./request"
require "./response"
require "./event"

module Obsctl
  module IPC
    # Union of messages that can cross the newline-delimited IPC transport.
    alias Message = Request | Response | Event

    # Encodes and decodes newline-delimited JSON IPC messages.
    class Codec
      # Encodes a single IPC message and appends the frame delimiter.
      def encode(message : Message) : String
        String.build do |io|
          message.to_json(io)
          io << '\n'
        end
      end

      # Decodes a single IPC frame into a typed message.
      def decode(line : String) : Message
        raise Domain::IpcProtocolError.new("empty IPC frame") if blank_frame?(line)

        root = JSON.parse(line)
        type = string_field(root, "type")

        case type
        when Request::TYPE_COMMAND
          decode_command(root)
        when Request::TYPE_SUBSCRIBE
          decode_subscribe(root)
        when Response::TYPE
          decode_response(root)
        when Event::TYPE
          decode_event(root)
        else
          raise Domain::IpcProtocolError.new("unknown IPC message type: #{type}")
        end
      rescue ex : JSON::ParseException
        raise Domain::IpcProtocolError.new("invalid IPC JSON: #{ex.message}")
      rescue TypeCastError | KeyError
        raise Domain::IpcProtocolError.new("invalid IPC frame")
      end

      private def decode_command(root : JSON::Any) : Request
        id = string_field(root, "id")
        command_root = root["command"]?
        raise Domain::IpcProtocolError.new("command request missing command payload") unless command_root

        command = CommandPayload.new(
          name: string_field(command_root, "name"),
          hidden: optional_string_array_field(command_root, "hidden"),
          rename_from: optional_string_field(command_root, "rename_from"),
          target: optional_string_field(command_root, "target"),
          percent: optional_int_field(command_root, "percent")
        )
        Request.new(id, Request::TYPE_COMMAND, command)
      end

      private def decode_subscribe(root : JSON::Any) : Request
        id = string_field(root, "id")
        topics_root = root["topics"]?
        raise Domain::IpcProtocolError.new("subscribe request missing topics") unless topics_root

        topics = topics_root.as_a.map do |topic|
          value = topic.as_s
          raise Domain::IpcProtocolError.new("subscribe topic cannot be empty") if value.empty?
          value
        end
        Request.new(id, Request::TYPE_SUBSCRIBE, nil, topics)
      end

      private def decode_response(root : JSON::Any) : Response
        error_root = root["error"]?
        error = if error_root
                  ErrorPayload.new(string_field(error_root, "code"), string_field(error_root, "message"))
                end

        Response.new(
          string_field(root, "id"),
          bool_field(root, "ok"),
          root["result"]?,
          error
        )
      end

      private def decode_event(root : JSON::Any) : Event
        Event.new(string_field(root, "topic"), root["data"]?)
      end

      private def string_field(root : JSON::Any, key : String) : String
        value = root[key].as_s
        raise Domain::IpcProtocolError.new("IPC field #{key} cannot be empty") if value.empty?
        value
      end

      private def optional_string_field(root : JSON::Any, key : String) : String?
        value = root[key]?
        return unless value
        text = value.as_s
        raise Domain::IpcProtocolError.new("IPC field #{key} cannot be empty") if text.empty?
        text
      end

      # An absent key and an explicit `null` both mean "not given"; an empty
      # array does not. `save_scene_profile` declares its list required, so
      # "this profile hides nothing" arrives as `[]` and has to survive as an
      # empty array rather than collapse into `nil`.
      private def optional_string_array_field(root : JSON::Any, key : String) : Array(String)?
        value = root[key]?
        return if value.nil? || value.raw.nil?

        entries = value.as_a?
        raise Domain::IpcProtocolError.new("IPC field #{key} must be an array") unless entries
        entries.map do |entry|
          text = entry.as_s?
          raise Domain::IpcProtocolError.new("IPC field #{key} must contain only strings") unless text
          text
        end
      end

      private def optional_int_field(root : JSON::Any, key : String) : Int32?
        root[key]?.try(&.as_i.to_i32)
      end

      private def bool_field(root : JSON::Any, key : String) : Bool
        root[key].as_bool
      end

      private def blank_frame?(line : String) : Bool
        line.each_char do |char|
          return false unless char.whitespace?
        end
        true
      end
    end
  end
end
