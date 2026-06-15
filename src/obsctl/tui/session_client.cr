require "../config/config"
require "../domain/aliases"
require "../domain/errors"
require "../ipc/protocol"
require "../obs/client"
require "../obs/protocol/event"
require "../obs/state/obs_snapshot"

module Obsctl
  module TUI
    # Boundary used by TUI sessions for state, commands, and pushed events.
    abstract class SessionClient
      # Opens the underlying session and prepares it for commands.
      abstract def connect : Nil
      # Closes the underlying session.
      abstract def close : Nil
      # Returns the current full OBS snapshot.
      abstract def snapshot : OBS::State::ObsSnapshot
      # Requests a scene change by user target.
      abstract def set_scene(target : String) : Nil
      # Requests a mute-state change by user target.
      abstract def mute(target : String, muted : Bool) : Nil
      # Requests a mute toggle by user target.
      abstract def toggle_mute(target : String) : Nil
      # Requests a volume change by user target and 0-100 percent.
      abstract def set_volume(target : String, percent : Int32) : Nil
      # Returns scene names from the current snapshot/source.
      abstract def scene_names : Array(String)
      # Returns audio input names from the current snapshot/source.
      abstract def input_names : Array(String)
      # Returns the next pushed OBS event when available.
      abstract def next_event : OBS::Protocol::Event?
      # Returns the next pushed state snapshot when available.
      abstract def next_snapshot : OBS::State::ObsSnapshot?
      # Returns the next pushed server log message when available.
      abstract def next_log : String?
      # Requests server-side config dumping.
      abstract def dump_config : Nil
      # Requests server-side config reload.
      abstract def reload_config : Nil
      # Requests server-owned OBS reconnection.
      abstract def reconnect_obs : Nil
      # Requests server-side config validation.
      abstract def validate_config : Nil
    end

    # Direct OBS adapter retained for explicit embedded-style sessions and tests.
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

      def next_log : String?
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

    # Normal TUI client that subscribes and sends commands over local IPC.
    class IpcSessionClient < SessionClient
      def initialize(@client : IPC::UnixClient = IPC::UnixClient.new)
        @session = nil.as(IPC::ClientSession?)
        @messages = Channel(IPC::Message).new(64)
        @pending_responses = Hash(String, Channel(IPC::Response)).new
        @pending_lock = Mutex.new
        @snapshot = nil.as(OBS::State::ObsSnapshot?)
        @events = [] of OBS::Protocol::Event
        @logs = [] of String
        @sequence = 0
      end

      # Connects to the local server, subscribes to state/events/logs, and starts
      # a reader fiber for pushed messages and command responses.
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

      # Closes the IPC session.
      def close : Nil
        @session.try(&.close)
      rescue
      ensure
        @session = nil
      end

      # Returns the latest pushed snapshot, requesting one if none has arrived.
      def snapshot : OBS::State::ObsSnapshot
        drain_messages
        existing = @snapshot
        return existing if existing

        result = send_command("get_snapshot")
        snapshot_from_json(result)
      end

      # Sends a scene-change command to the local server.
      def set_scene(target : String) : Nil
        send_command("set_scene", target)
      end

      # Sends a mute or unmute command to the local server.
      def mute(target : String, muted : Bool) : Nil
        send_command(muted ? "mute" : "unmute", target)
      end

      # Sends a toggle-mute command to the local server.
      def toggle_mute(target : String) : Nil
        send_command("toggle_mute", target)
      end

      # Sends a volume command to the local server.
      def set_volume(target : String, percent : Int32) : Nil
        send_command("set_volume", target, percent)
      end

      # Returns scene names from the latest server snapshot.
      def scene_names : Array(String)
        snapshot.scenes.map(&.name)
      end

      # Returns input names from the latest server snapshot.
      def input_names : Array(String)
        snapshot.audio_inputs.map(&.name)
      end

      # Returns the next queued OBS event from server fanout.
      def next_event : OBS::Protocol::Event?
        drain_messages
        @events.shift?
      end

      # Returns the latest pushed server state snapshot.
      def next_snapshot : OBS::State::ObsSnapshot?
        drain_messages
        @snapshot
      end

      # Returns the next queued server log message.
      def next_log : String?
        drain_messages
        @logs.shift?
      end

      # Requests server-side dump-config execution.
      def dump_config : Nil
        send_command("dump_config")
      end

      # Requests server-side config reload.
      def reload_config : Nil
        send_command("reload_config")
      end

      # Requests explicit OBS reconnection from the server.
      def reconnect_obs : Nil
        send_command("reconnect_obs")
      end

      # Requests server-side config validation.
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
        when "logs"
          data = event.data
          return unless data

          @logs << log_message(data)
        end
      end

      private def log_message(data : JSON::Any) : String
        level = data["level"]?.try(&.as_s?) || "info"
        code = data["code"]?.try(&.as_s?)
        message = data["message"]?.try(&.as_s?) || "server log"

        if code
          "#{level} #{code}: #{message}"
        else
          "#{level}: #{message}"
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
