require "json"
require "../domain/errors"
require "./request"
require "./response"
require "./event"

module Obsctl
  module IPC
    alias Message = Request | Response | Event

    class Codec
      def encode(message : Message) : String
        message.to_json + "\n"
      end

      def decode(line : String) : Message
        payload = line.strip
        raise Domain::IpcProtocolError.new("empty IPC frame") if payload.empty?

        root = JSON.parse(payload)
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
      rescue ex : TypeCastError | KeyError
        raise Domain::IpcProtocolError.new("invalid IPC frame")
      end

      private def decode_command(root : JSON::Any) : Request
        id = string_field(root, "id")
        command_root = root["command"]?
        raise Domain::IpcProtocolError.new("command request missing command payload") unless command_root

        command = CommandPayload.new(
          string_field(command_root, "name"),
          optional_string_field(command_root, "target"),
          optional_int_field(command_root, "percent")
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
        return nil unless value
        text = value.as_s
        raise Domain::IpcProtocolError.new("IPC field #{key} cannot be empty") if text.empty?
        text
      end

      private def optional_int_field(root : JSON::Any, key : String) : Int32?
        root[key]?.try(&.as_i.to_i32)
      end

      private def bool_field(root : JSON::Any, key : String) : Bool
        root[key].as_bool
      end
    end
  end
end
