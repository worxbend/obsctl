require "../config/config"
require "../domain/aliases"
require "../domain/errors"
require "../ipc/protocol"
require "../obs/client"
require "../obs/protocol/event"
require "../obs/state/obs_snapshot"

module Obsctl
  module TUI
    abstract class SessionClient
      abstract def connect : Nil
      abstract def close : Nil
      abstract def snapshot : OBS::State::ObsSnapshot
      abstract def set_scene(target : String) : Nil
      abstract def mute(target : String, muted : Bool) : Nil
      abstract def toggle_mute(target : String) : Nil
      abstract def set_volume(target : String, percent : Int32) : Nil
      abstract def scene_names : Array(String)
      abstract def input_names : Array(String)
      abstract def next_event : OBS::Protocol::Event?
      abstract def next_snapshot : OBS::State::ObsSnapshot?
      abstract def dump_config : Nil
      abstract def reload_config : Nil
      abstract def reconnect_obs : Nil
      abstract def validate_config : Nil
    end

    class ObsSessionClient < SessionClient
      def initialize(@config : Config::Config)
        @client = OBS::Client.new(@config)
      end

      def connect : Nil
        @client.connect
      end

      def close : Nil
        @client.close
      end

      def snapshot : OBS::State::ObsSnapshot
        @client.snapshot
      end

      def set_scene(target : String) : Nil
        scene = Domain::Aliases.resolve_scene(@config, target)
        @client.set_scene(scene.name)
      end

      def mute(target : String, muted : Bool) : Nil
        input = Domain::Aliases.resolve_audio(@config, target)
        @client.mute(input.name, muted)
      end

      def toggle_mute(target : String) : Nil
        input = Domain::Aliases.resolve_audio(@config, target)
        @client.toggle_mute(input.name)
      end

      def set_volume(target : String, percent : Int32) : Nil
        input = Domain::Aliases.resolve_audio(@config, target)
        @client.set_volume(input.name, percent)
      end

      def scene_names : Array(String)
        @client.scene_names
      end

      def input_names : Array(String)
        @client.input_names
      end

      def next_event : OBS::Protocol::Event?
        select
        when event = @client.events.receive
          event
        when timeout(0.milliseconds)
          nil
        end
      end

      def next_snapshot : OBS::State::ObsSnapshot?
        nil
      end

      def dump_config : Nil
      end

      def reload_config : Nil
      end

      def reconnect_obs : Nil
        close
        connect
      end

      def validate_config : Nil
      end
    end

    class IpcSessionClient < SessionClient
      def initialize(@client : IPC::UnixClient = IPC::UnixClient.new)
        @session = nil.as(IPC::ClientSession?)
        @messages = Channel(IPC::Message).new(64)
        @pending_responses = Hash(String, Channel(IPC::Response)).new
        @pending_lock = Mutex.new
        @snapshot = nil.as(OBS::State::ObsSnapshot?)
        @events = [] of OBS::Protocol::Event
        @sequence = 0
      end

      def connect : Nil
        close
        session = @client.connect
        @session = session
        request = IPC::Request.new(next_id, IPC::Request::TYPE_SUBSCRIBE, nil, ["state", "events", "logs"])
        session.write_message(request)
        response = session.read_message.as?(IPC::Response)
        raise Domain::IpcProtocolError.new("server closed IPC connection before subscription acknowledgement") unless response
        raise_response_error(response) unless response.ok

        initial = session.read_message.as?(IPC::Event)
        apply_event(initial) if initial
        spawn(name: "obsctl-tui-ipc-reader") { read_messages(session) }
      rescue ex : Domain::IpcConnectionFailed
        raise Domain::ServerUnavailable.new
      end

      def close : Nil
        @session.try(&.close)
      rescue
      ensure
        @session = nil
      end

      def snapshot : OBS::State::ObsSnapshot
        drain_messages
        existing = @snapshot
        return existing if existing

        result = send_command("get_snapshot")
        snapshot_from_json(result)
      end

      def set_scene(target : String) : Nil
        send_command("set_scene", target)
      end

      def mute(target : String, muted : Bool) : Nil
        send_command(muted ? "mute" : "unmute", target)
      end

      def toggle_mute(target : String) : Nil
        send_command("toggle_mute", target)
      end

      def set_volume(target : String, percent : Int32) : Nil
        send_command("set_volume", target, percent)
      end

      def scene_names : Array(String)
        snapshot.scenes.map(&.name)
      end

      def input_names : Array(String)
        snapshot.audio_inputs.map(&.name)
      end

      def next_event : OBS::Protocol::Event?
        drain_messages
        @events.shift?
      end

      def next_snapshot : OBS::State::ObsSnapshot?
        drain_messages
        @snapshot
      end

      def dump_config : Nil
        send_command("dump_config")
      end

      def reload_config : Nil
        send_command("reload_config")
      end

      def reconnect_obs : Nil
        send_command("reconnect_obs")
      end

      def validate_config : Nil
        send_command("validate_config")
      end

      private def send_command(name : String, target : String? = nil, percent : Int32? = nil) : JSON::Any
        session = @session || raise Domain::ServerUnavailable.new
        request = nil.as(IPC::Request?)
        request = IPC::Request.new(next_id, IPC::Request::TYPE_COMMAND, IPC::CommandPayload.new(name, target, percent))
        responses = Channel(IPC::Response).new(1)
        @pending_lock.synchronize { @pending_responses[request.id] = responses }
        session.write_message(request)

        select
        when response = responses.receive
          raise_response_error(response) unless response.ok
          response.result || JSON.parse("{}")
        when timeout(5.seconds)
          raise Domain::IpcProtocolError.new("timed out waiting for server response")
        end
      rescue ex : IO::Error
        raise Domain::IpcConnectionFailed.new(ex.message || "IPC connection failed")
      ensure
        if request
          @pending_lock.synchronize { @pending_responses.delete(request.id) }
        end
      end

      private def read_messages(session : IPC::ClientSession) : Nil
        while message = session.read_message
          case message
          when IPC::Response
            dispatch_response(message)
          when IPC::Event
            @messages.send(message)
          end
        end
      rescue
      end

      private def dispatch_response(response : IPC::Response) : Nil
        channel = @pending_lock.synchronize { @pending_responses[response.id]? }
        channel.try(&.send(response))
      end

      private def drain_messages : Nil
        loop do
          select
          when message = @messages.receive
            apply_event(message) if message.is_a?(IPC::Event)
          when timeout(0.milliseconds)
            break
          end
        end
      end

      private def apply_event(event : IPC::Event?) : Nil
        return unless event

        case event.topic
        when "state"
          data = event.data
          return unless data

          @snapshot = snapshot_from_json(data)
        when "events"
          data = event.data
          return unless data

          event_type = data["event_type"]?.try(&.as_s?)
          return unless event_type

          @events << OBS::Protocol::Event.new(event_type, data["event_data"]?)
        end
      end

      private def snapshot_from_json(data : JSON::Any) : OBS::State::ObsSnapshot
        OBS::State::ObsSnapshot.new(
          connected: data["connected"]?.try(&.as_bool?) || false,
          obs_studio_version: data["obs_studio_version"]?.try(&.as_s?),
          obs_websocket_version: data["obs_websocket_version"]?.try(&.as_s?),
          current_scene: data["current_scene"]?.try(&.as_s?),
          scenes: scene_states(data["scenes"]?),
          audio_inputs: audio_states(data["audio_inputs"]?),
          last_error: data["last_error"]?.try(&.as_s?),
          updated_at: parse_time(data["updated_at"]?.try(&.as_s?))
        )
      end

      private def scene_states(root : JSON::Any?) : Array(OBS::State::SceneState)
        return [] of OBS::State::SceneState unless root

        root.as_a.map do |scene|
          OBS::State::SceneState.new(
            name: scene["name"].as_s,
            alias: scene["alias"]?.try(&.as_s?),
            shortcut: scene["shortcut"]?.try(&.as_s?),
            group: scene["group"]?.try(&.as_s?),
            active: scene["active"]?.try(&.as_bool?) || false
          )
        end
      end

      private def audio_states(root : JSON::Any?) : Array(OBS::State::AudioState)
        return [] of OBS::State::AudioState unless root

        root.as_a.map do |input|
          OBS::State::AudioState.new(
            name: input["name"].as_s,
            alias: input["alias"]?.try(&.as_s?),
            shortcut: input["shortcut"]?.try(&.as_s?),
            muted: input["muted"]?.try(&.as_bool?),
            volume_mul: number(input["volume_mul"]?),
            volume_db: number(input["volume_db"]?),
            volume_percent: input["volume_percent"]?.try(&.as_i?.try(&.to_i32))
          )
        end
      end

      private def number(value : JSON::Any?) : Float64?
        value.try { |item| item.as_f? || item.as_i?.try(&.to_f64) }
      end

      private def parse_time(value : String?) : Time
        return Time.utc unless value
        Time.parse_rfc3339(value)
      rescue
        Time.utc
      end

      private def raise_response_error(response : IPC::Response) : NoReturn
        error = response.error
        raise Domain::IpcProtocolError.new("server returned an invalid error response") unless error

        case error.code
        when "OBS_UNAVAILABLE"
          raise Domain::ObsUnavailable.new(error.message)
        when "COMMAND_PARSE_ERROR"
          raise Domain::CommandParseError.new(error.message)
        when "CONFIG_ERROR"
          raise Domain::ConfigInvalid.new(error.message)
        else
          raise Domain::RemoteCommandFailed.new(error.message, Domain::ExitCode::ObsRequest)
        end
      end

      private def next_id : String
        @sequence += 1
        "tui-%06d" % @sequence
      end
    end
  end
end
