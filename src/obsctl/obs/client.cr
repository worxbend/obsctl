require "http/web_socket"
require "json"
require "./auth"
require "./connection"
require "./protocol/request_id"
require "./protocol/request"
require "./protocol/response"
require "./protocol/event"
require "./protocol/event_subscription"
require "./protocol/message"
require "./requests/version"
require "./requests/scenes"
require "./requests/audio"
require "./state/obs_snapshot"
require "../config/config"
require "../domain/errors"
require "../domain/aliases"

module Obsctl
  module OBS
    # obs-websocket 5.x client used by the server-owned OBS supervisor.
    class Client
      def initialize(
        @config : Config::Config,
        @event_subscriptions : Int32? = nil,
      )
        @request_ids = Protocol::RequestId.new
        @identified = false
        @ws = uninitialized HTTP::WebSocket
        @system_frames = Channel(String | Exception).new(8)
        @events = Channel(Protocol::Event).new
        @pending = {} of String => Channel(Protocol::Response | Exception)
        @pending_lock = Mutex.new
      end

      # Channel of parsed OBS events from opcode 5 frames.
      getter events

      # Returns true after Identify completes and the underlying socket is open.
      def connected? : Bool
        @identified && !@ws.closed?
      end

      # Opens the WebSocket, performs Hello/Identify/Identified, and starts the
      # reader fiber used for events and request responses.
      def connect : Nil
        @ws = Connection.new(@config.connection).connect
        @ws.on_message { |message| handle_frame(message) }
        @ws.on_close { fail_all_pending(Domain::ConnectionFailed.new("OBS WebSocket closed")) }
        spawn do
          begin
            @ws.run
          rescue ex
            fail_all_pending(Domain::ConnectionFailed.new("OBS WebSocket reader failed: #{ex.message}"))
          end
        end
        hello = read_system_frame
        identify(hello)
        @identified = true
      end

      # Closes the WebSocket and marks this client as no longer identified.
      def close : Nil
        @identified = false
        @ws.close unless @ws.closed?
      rescue
      end

      # Sends a typed obs-websocket request frame and waits for the matching
      # request ID response or timeout.
      def request(request_type : String, data : JSON::Any? = nil) : Protocol::Response
        raise Domain::ConnectionFailed.new("OBS client is not identified") unless @identified
        id = @request_ids.next
        responses = Channel(Protocol::Response | Exception).new(1)
        @pending_lock.synchronize { @pending[id] = responses }
        begin
          @ws.send(Protocol::Request.new(request_type, id, data).to_frame)
        rescue ex
          raise Domain::ConnectionFailed.new("failed to send OBS request #{request_type}: #{ex.message}")
        end
        timeout = @config.connection.request_timeout_ms.milliseconds
        select
        when result = responses.receive
          raise result if result.is_a?(Exception)
          response = result
          unless response.request_status.result
            raise Domain::ObsRequestFailed.new(request_type, response.request_status.comment || "request returned failure")
          end
          return response
        when timeout(timeout)
          raise Domain::RequestTimeout.new(request_type)
        end
      ensure
        @pending_lock.synchronize { @pending.delete(id) } if id
      end

      # Fetches OBS and obs-websocket version metadata.
      def version : JSON::Any
        request(Requests::Version::GET_VERSION).response_data || JSON.parse("{}")
      end

      # Returns the current OBS scene names in OBS order.
      def scene_names : Array(String)
        data = request(Requests::Scenes::GET_SCENE_LIST).response_data || JSON.parse("{}")
        data["scenes"].as_a.map { |scene| scene["sceneName"].as_s }
      end

      # Returns the current OBS program scene name when available.
      def current_scene : String?
        data = request(Requests::Scenes::GET_CURRENT_PROGRAM_SCENE).response_data || JSON.parse("{}")
        data["currentProgramSceneName"]?.try(&.as_s)
      end

      # Changes the current OBS program scene by exact OBS scene name.
      def set_scene(name : String) : Nil
        request(Requests::Scenes::SET_CURRENT_PROGRAM_SCENE, Requests::Scenes.set_current_program_scene(name))
      end

      # Returns current OBS input names.
      def input_names : Array(String)
        data = request(Requests::Audio::GET_INPUT_LIST).response_data || JSON.parse("{}")
        data["inputs"].as_a.map { |input| input["inputName"].as_s }
      end

      # Returns mute state for an OBS input by exact OBS input name.
      def input_muted(name : String) : Bool?
        data = request(Requests::Audio::GET_INPUT_MUTE, Requests::Audio.input_name(name)).response_data || JSON.parse("{}")
        data["inputMuted"]?.try(&.as_bool)
      end

      # Returns OBS input volume in multiplier, dB, and user-facing percent.
      def input_volume(name : String) : NamedTuple(mul: Float64?, db: Float64?, percent: Int32?)
        data = request(Requests::Audio::GET_INPUT_VOLUME, Requests::Audio.input_name(name)).response_data || JSON.parse("{}")
        mul = number(data, "inputVolumeMul")
        db = number(data, "inputVolumeDb")
        percent = mul.try { |value| (value * 100).round.to_i32.clamp(0, 100) }
        {mul: mul, db: db, percent: percent}
      end

      # Sets mute state for an OBS input by exact OBS input name.
      def mute(name : String, muted : Bool) : Nil
        request(Requests::Audio::SET_INPUT_MUTE, Requests::Audio.set_mute(name, muted))
      end

      # Toggles mute state for an OBS input by exact OBS input name.
      def toggle_mute(name : String) : Nil
        request(Requests::Audio::TOGGLE_INPUT_MUTE, Requests::Audio.input_name(name))
      end

      # Sets OBS input volume using a user-facing 0-100 percentage.
      def set_volume(name : String, percent : Int32) : Nil
        request(Requests::Audio::SET_INPUT_VOLUME, Requests::Audio.set_volume(name, Domain::Aliases.volume_percent_to_mul(percent)))
      end

      # Fetches a full state snapshot for publication to local IPC clients.
      def snapshot : State::ObsSnapshot
        version_data = version
        current = current_scene
        scenes = scene_names.map do |name|
          configured = @config.scenes.find { |scene| scene.name == name }
          State::SceneState.new(
            name: name,
            alias: configured.try(&.alias),
            shortcut: configured.try(&.shortcut),
            group: configured.try(&.group),
            active: current == name
          )
        end
        audio = input_names.map do |name|
          configured = @config.audio.inputs.find { |input| input.name == name }
          muted = input_muted(name)
          volume = input_volume(name)
          State::AudioState.new(
            name: name,
            alias: configured.try(&.alias),
            shortcut: configured.try(&.shortcut),
            muted: muted,
            volume_mul: volume[:mul],
            volume_db: volume[:db],
            volume_percent: volume[:percent]
          )
        end
        State::ObsSnapshot.new(
          connected: true,
          obs_studio_version: version_data["obsVersion"]?.try(&.as_s),
          obs_websocket_version: version_data["obsWebSocketVersion"]?.try(&.as_s),
          current_scene: current,
          scenes: scenes,
          audio_inputs: audio
        )
      end

      private def identify(hello_frame : String) : Nil
        hello = JSON.parse(hello_frame)
        raise Domain::ConnectionFailed.new("expected OBS Hello frame") unless hello["op"].as_i == 0
        data = hello["d"]
        identify_data = {} of String => JSON::Any
        identify_data["rpcVersion"] = JSON::Any.new(data["rpcVersion"].as_i64)
        if event_subscriptions = @event_subscriptions
          identify_data["eventSubscriptions"] = JSON::Any.new(event_subscriptions.to_i64)
        end

        if auth = data["authentication"]?
          password = password_from_config
          raise Domain::AuthenticationFailed.new("OBS requires authentication but no password is configured") unless password
          salt = auth["salt"].as_s
          challenge = auth["challenge"].as_s
          identify_data["authentication"] = JSON::Any.new(Auth.authentication(password, salt, challenge))
        end

        frame = JSON.build do |json|
          json.object do
            json.field "op", 1
            json.field "d", identify_data
          end
        end
        @ws.send(frame)
        identified = read_system_frame
        parsed = JSON.parse(identified)
        raise Domain::AuthenticationFailed.new unless parsed["op"].as_i == 2
      end

      private def password_from_config : String?
        if env_name = @config.connection.password_env
          value = ENV[env_name]?
          return value unless value.try(&.empty?)
        end
        @config.connection.password
      end

      private def read_system_frame : String
        timeout = @config.connection.request_timeout_ms.milliseconds
        select
        when result = @system_frames.receive
          raise result if result.is_a?(Exception)
          result
        when timeout(timeout)
          raise Domain::ConnectionFailed.new("timed out waiting for OBS WebSocket")
        end
      end

      private def number(data : JSON::Any, key : String) : Float64?
        value = data[key]?
        return nil unless value
        value.as_f? || value.as_i?.try(&.to_f64)
      end

      private def handle_frame(frame : String) : Nil
        case Protocol::Message.opcode(frame)
        when 7
          route_response(frame)
        when 5
          if event = Protocol::Event.from_frame(frame)
            spawn { @events.send(event) }
          end
        else
          @system_frames.send(frame)
        end
      rescue ex
        fail_protocol_error(ex)
      end

      private def route_response(frame : String) : Nil
        response = Protocol::Response.from_frame(frame)
        return unless response

        channel = @pending_lock.synchronize { @pending[response.request_id]? }
        channel.try(&.send(response))
      rescue ex
        fail_protocol_error(ex)
      end

      private def fail_protocol_error(error : Exception) : Nil
        fail_all_pending(Domain::ConnectionFailed.new("OBS WebSocket protocol error: #{error.message}"))
      end

      private def fail_all_pending(error : Exception) : Nil
        @identified = false
        pending = @pending_lock.synchronize do
          channels = @pending.values.to_a
          @pending.clear
          channels
        end
        pending.each { |channel| channel.send(error) }
        spawn { @system_frames.send(error) }
      end
    end
  end
end
