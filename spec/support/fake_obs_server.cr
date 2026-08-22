require "http/server"
require "http/web_socket"
require "json"
require "../../src/obsctl/config/config"
require "../../src/obsctl/obs/protocol/event_subscription"

module Obsctl
  module SpecSupport
    class FakeObsServer
      # `audio: false` models an input with no audio track — an image, colour,
      # or silent browser source. `GetInputList` still returns it, but OBS
      # refuses to report its mute or volume.
      record AudioInput,
        name : String,
        kind : String = "input",
        muted : Bool = false,
        volume_mul : Float64 = 1.0,
        volume_db : Float64 = 0.0,
        audio : Bool = true

      # Verbatim from obs-websocket 5.x: `RequestStatus::InvalidResourceState`
      # and the comment it returns for a mute or volume read on an input with
      # no audio track.
      AUDIO_UNSUPPORTED_CODE    = 604
      AUDIO_UNSUPPORTED_COMMENT = "The specified input does not support audio."

      getter host : String
      getter port : Int32

      @server : HTTP::Server
      @mutex = Mutex.new
      @send_mutex = Mutex.new
      @identify_data = nil.as(JSON::Any?)
      @connection_attempt_count = 0_i64
      @identify_count = 0_i64
      @request_count = 0_i64
      @close_count = 0_i64
      @next_websocket_connection_id = 0_i64
      @closed_websocket_connection_ids = [] of Int64
      @connection_notifications = Channel(Nil).new(16)
      @accepted_websocket_connection_notifications = Channel(Int64).new(16)
      @identify_notifications = Channel(JSON::Any).new(16)
      @request_notifications = Channel(String).new(16)
      @delayed_response_notifications = Channel(String).new(16)
      @close_notifications = Channel(Nil).new(16)
      @closed_websocket_connection_notifications = Channel(Int64).new(16)
      @connection_or_identify_notifications = Channel(String).new(16)
      @websockets = [] of HTTP::WebSocket
      # Real obs-websocket delivers an event only to clients whose Identify
      # subscribed to its category, so the fake filters the same way. Without
      # that, a spec proves a handler runs without proving the daemon ever
      # receives the event.
      @event_subscriptions = {} of HTTP::WebSocket => Int64

      def initialize(
        @scenes : Array(String) = ["Main Camera", "Screen Share", "BRB"],
        @current_scene : String = "Main Camera",
        @inputs : Array(AudioInput) = [
          AudioInput.new("Mic/Aux", "input", false, 0.7, -3.0),
          AudioInput.new("Desktop Audio", "output", true, 0.4, -8.0),
        ],
        port : Int32? = nil,
        @request_delays : Hash(String, Time::Span) = {} of String => Time::Span,
        @request_timeout_ms : Int32 = 500,
        @streaming : Bool = false,
        @recording : Bool = false,
        @record_paused : Bool = false,
        @record_output_path : String = "/tmp/obsctl-fake-recording.mkv",
        @profiles : Array(String) = ["Default", "Streaming"],
        @current_profile : String = "Default",
        @scene_collections : Array(String) = ["Podcast", "Gaming"],
        @current_scene_collection : String = "Podcast",
        @stream_bytes : Int64 = 1_000_000_i64,
        @stream_bytes_per_status : Int64 = 0_i64,
        @authentication : Bool = false,
        # Rejects Identify the way obs-websocket rejects a wrong password: close
        # code 4009, after the socket is already open. Lets specs reach the
        # "connected enough to hold an fd, not connected enough to be
        # identified" state that a leak can hide in.
        @reject_identify : Bool = false,
        # Sends a Hello whose `d` object omits `rpcVersion`, the way a peer
        # that is not obs-websocket 5.x would. Lets a spec prove the handshake
        # reports a protocol mismatch instead of leaking a raw `KeyError`.
        @omit_hello_rpc_version : Bool = false,
      )
        @host = "127.0.0.1"
        @server = HTTP::Server.new([websocket_handler])
        address = @server.bind_tcp(@host, port || 0)
        @port = address.port
      end

      def start : self
        spawn(name: "fake-obs-websocket") { @server.listen }
        Fiber.yield
        self
      end

      def stop : Nil
        @server.close
        close_connections
      rescue
      end

      def close_connections(
        code : HTTP::WebSocket::CloseCode | Int32? = nil,
        message : String? = nil,
      ) : Nil
        sockets = @mutex.synchronize do
          existing = @websockets.dup
          @websockets.clear
          existing
        end
        sockets.each do |websocket|
          websocket.close(code, message)
        rescue
        end
      end

      def config : Config::Config
        Config::Config.new(
          connection: Config::ConnectionConfig.new(
            host: @host,
            port: @port,
            password_env: "",
            request_timeout_ms: @request_timeout_ms
          ),
          scenes: [
            Config::SceneConfig.new("Main Camera", "main", "1", "primary"),
            Config::SceneConfig.new("Screen Share", "screen", "2", "primary"),
          ],
          audio: Config::AudioConfig.new([
            Config::AudioInputConfig.new("Mic/Aux", "mic", "m", "input"),
            Config::AudioInputConfig.new("Desktop Audio", "desktop", "d", "output"),
          ])
        )
      end

      def current_scene : String
        @mutex.synchronize { @current_scene }
      end

      def input(name : String) : AudioInput?
        @mutex.synchronize { @inputs.find { |input| input.name == name } }
      end

      def streaming? : Bool
        @mutex.synchronize { @streaming }
      end

      def recording? : Bool
        @mutex.synchronize { @recording }
      end

      def record_paused? : Bool
        @mutex.synchronize { @record_paused }
      end

      def record_output_path : String
        @mutex.synchronize { @record_output_path }
      end

      def current_profile : String
        @mutex.synchronize { @current_profile }
      end

      def current_scene_collection : String
        @mutex.synchronize { @current_scene_collection }
      end

      def identify_data : JSON::Any?
        @mutex.synchronize { @identify_data }
      end

      def connection_attempt_count : Int64
        @mutex.synchronize { @connection_attempt_count }
      end

      def identify_count : Int64
        @mutex.synchronize { @identify_count }
      end

      def request_count : Int64
        @mutex.synchronize { @request_count }
      end

      def close_count : Int64
        @mutex.synchronize { @close_count }
      end

      def next_connection_attempt(timeout : Time::Span = 1.second) : Bool
        select
        when @connection_notifications.receive
          true
        when timeout(timeout)
          false
        end
      end

      def next_accepted_websocket_connection_id(timeout : Time::Span = 1.second) : Int64?
        select
        when connection_id = @accepted_websocket_connection_notifications.receive
          connection_id
        when timeout(timeout)
          nil
        end
      end

      def next_identify(timeout : Time::Span = 1.second) : JSON::Any?
        select
        when identify = @identify_notifications.receive
          identify
        when timeout(timeout)
          nil
        end
      end

      def next_identify_received(timeout : Time::Span = 1.second) : JSON::Any?
        next_identify(timeout)
      end

      def next_request(timeout : Time::Span = 1.second) : String?
        select
        when request_type = @request_notifications.receive
          request_type
        when timeout(timeout)
          nil
        end
      end

      def next_obs_request_type(timeout : Time::Span = 1.second) : String?
        next_request(timeout)
      end

      def next_delayed_response(timeout : Time::Span = 1.second) : String?
        select
        when request_type = @delayed_response_notifications.receive
          request_type
        when timeout(timeout)
          nil
        end
      end

      def next_close(timeout : Time::Span = 1.second) : Bool
        select
        when @close_notifications.receive
          true
        when timeout(timeout)
          false
        end
      end

      def next_close_observed(timeout : Time::Span = 1.second) : Bool
        next_close(timeout)
      end

      def next_closed_websocket_connection_id(timeout : Time::Span = 1.second) : Int64?
        select
        when connection_id = @closed_websocket_connection_notifications.receive
          connection_id
        when timeout(timeout)
          nil
        end
      end

      def assert_websocket_connection_closed(connection_id : Int64, timeout : Time::Span = 1.second) : Nil
        deadline = Time.instant + timeout

        loop do
          return if websocket_connection_closed?(connection_id)

          remaining = deadline - Time.instant
          break if remaining <= 0.seconds

          select
          when closed_connection_id = @closed_websocket_connection_notifications.receive
            return if closed_connection_id == connection_id
          when timeout(remaining)
            break
          end
        end

        return if websocket_connection_closed?(connection_id)

        raise "fake OBS did not observe WebSocket connection #{connection_id} close within #{timeout}"
      end

      def no_identify_or_connection_attempt?(timeout : Time::Span = 100.milliseconds) : Bool
        start_connection_attempt_count, start_identify_count = identify_or_connection_counts
        no_identify_or_connection_attempt_since?(
          start_connection_attempt_count,
          start_identify_count,
          timeout
        )
      end

      def assert_no_identify_or_connection_attempt(timeout : Time::Span = 100.milliseconds) : Nil
        start_connection_attempt_count, start_identify_count = identify_or_connection_counts
        return if no_identify_or_connection_attempt_since?(
                    start_connection_attempt_count,
                    start_identify_count,
                    timeout
                  )

        connection_attempt_count, identify_count = identify_or_connection_counts
        raise "fake OBS received unexpected Identify or connection attempt within #{timeout} " \
              "(connections: #{start_connection_attempt_count} -> #{connection_attempt_count}, " \
              "identifies: #{start_identify_count} -> #{identify_count})"
      end

      def emit_current_scene_changed(scene_name : String) : Nil
        @mutex.synchronize { @current_scene = scene_name if @scenes.includes?(scene_name) }
        broadcast_event("CurrentProgramSceneChanged", {"sceneName" => scene_name}, OBS::Protocol::EventSubscription::SCENES)
      end

      def emit_input_mute_changed(input_name : String, muted : Bool) : Nil
        @mutex.synchronize { update_input(input_name, muted: muted) }
        broadcast_event("InputMuteStateChanged", {"inputName" => input_name, "inputMuted" => muted}, OBS::Protocol::EventSubscription::INPUTS)
      end

      # Streaming toggled outside obsctl, as the OBS UI or another client would
      # do it: OBS's own state moves and the event follows.
      def emit_stream_state_changed(active : Bool) : Nil
        @mutex.synchronize { @streaming = active }
        broadcast_event(
          "StreamStateChanged",
          {"outputActive" => active, "outputState" => active ? "OBS_WEBSOCKET_OUTPUT_STARTED" : "OBS_WEBSOCKET_OUTPUT_STOPPED"},
          OBS::Protocol::EventSubscription::OUTPUTS
        )
      end

      def emit_record_state_changed(active : Bool) : Nil
        @mutex.synchronize { @recording = active }
        broadcast_event(
          "RecordStateChanged",
          {"outputActive" => active, "outputState" => active ? "OBS_WEBSOCKET_OUTPUT_STARTED" : "OBS_WEBSOCKET_OUTPUT_STOPPED"},
          OBS::Protocol::EventSubscription::OUTPUTS
        )
      end

      # Moves OBS's output state without announcing it, standing in for an
      # event obsctl never gets: a dropped frame, or an OBS build that does not
      # send one. Only the periodic telemetry poll can notice this.
      def set_output_state(streaming : Bool? = nil, recording : Bool? = nil) : Nil
        @mutex.synchronize do
          streaming.try { |value| @streaming = value }
          recording.try { |value| @recording = value }
        end
      end

      def emit_raw_frame(frame : String) : Nil
        sockets = @mutex.synchronize { @websockets.dup }
        sockets.each do |websocket|
          send_frame(websocket, frame)
        rescue
        end
      end

      private def websocket_handler : HTTP::WebSocketHandler
        HTTP::WebSocketHandler.new do |websocket, _context|
          connection_id = @mutex.synchronize do
            @next_websocket_connection_id += 1
            @websockets << websocket
            @connection_attempt_count += 1
            @next_websocket_connection_id
          end
          notify_connection_attempt(connection_id)
          websocket.on_close do
            @mutex.synchronize do
              @websockets.delete(websocket)
              @event_subscriptions.delete(websocket)
              @close_count += 1
              @closed_websocket_connection_ids << connection_id
            end
            notify_close(connection_id)
          end
          send_frame(websocket, hello_frame)
          websocket.on_message do |message|
            handle_message(websocket, message)
          end
        end
      end

      private def handle_message(websocket : HTTP::WebSocket, message : String) : Nil
        frame = JSON.parse(message)
        case frame["op"].as_i
        when 1
          identify = frame["d"]
          @mutex.synchronize do
            @identify_data = identify
            @identify_count += 1
            # obs-websocket defaults to every non-high-volume category when a
            # client omits the field.
            @event_subscriptions[websocket] = identify["eventSubscriptions"]?.try(&.as_i64?) || OBS::Protocol::EventSubscription::ALL.to_i64
          end
          notify_identify(identify)
          if @reject_identify
            websocket.close(4009, "Authentication failed")
          else
            send_frame(websocket, identified_frame)
          end
        when 6
          request = frame["d"]
          request_type = request["requestType"].as_s
          notify_request(request_type)
          if delay = @request_delays[request_type]?
            spawn do
              sleep delay
              send_frame(websocket, response_frame(request))
            rescue
            ensure
              notify_delayed_response(request_type)
            end
          else
            send_frame(websocket, response_frame(request))
          end
        end
      end

      private def hello_frame : String
        JSON.build do |json|
          json.object do
            json.field "op", 0
            json.field "d" do
              json.object do
                json.field "obsWebSocketVersion", "5.4.0"
                json.field "rpcVersion", 1 unless @omit_hello_rpc_version
                if @authentication
                  json.field "authentication" do
                    json.object do
                      json.field "challenge", "test-challenge"
                      json.field "salt", "test-salt"
                    end
                  end
                end
              end
            end
          end
        end
      end

      private def identify_or_connection_counts
        @mutex.synchronize { {@connection_attempt_count, @identify_count} }
      end

      private def websocket_connection_closed?(connection_id : Int64) : Bool
        @mutex.synchronize { @closed_websocket_connection_ids.includes?(connection_id) }
      end

      private def identify_or_connection_counts_changed?(
        start_connection_attempt_count : Int64,
        start_identify_count : Int64,
      ) : Bool
        connection_attempt_count, identify_count = identify_or_connection_counts
        connection_attempt_count > start_connection_attempt_count || identify_count > start_identify_count
      end

      private def no_identify_or_connection_attempt_since?(
        start_connection_attempt_count : Int64,
        start_identify_count : Int64,
        timeout : Time::Span,
      ) : Bool
        deadline = Time.instant + timeout

        loop do
          remaining = deadline - Time.instant
          return true if remaining <= 0.seconds

          select
          when @connection_or_identify_notifications.receive
            return false if identify_or_connection_counts_changed?(
                              start_connection_attempt_count,
                              start_identify_count
                            )
          when timeout(remaining)
            return !identify_or_connection_counts_changed?(
              start_connection_attempt_count,
              start_identify_count
            )
          end
        end
      end

      private def notify_connection_attempt(connection_id : Int64) : Nil
        select
        when @connection_notifications.send(nil)
        else
        end

        select
        when @accepted_websocket_connection_notifications.send(connection_id)
        else
        end

        notify_connection_or_identify("connection")
      end

      private def notify_request(request_type : String) : Nil
        @mutex.synchronize { @request_count += 1 }
        select
        when @request_notifications.send(request_type)
        else
        end
      end

      private def notify_identify(data : JSON::Any) : Nil
        select
        when @identify_notifications.send(data)
        else
        end

        notify_connection_or_identify("identify")
      end

      private def notify_delayed_response(request_type : String) : Nil
        select
        when @delayed_response_notifications.send(request_type)
        else
        end
      end

      private def notify_close(connection_id : Int64) : Nil
        select
        when @close_notifications.send(nil)
        else
        end

        select
        when @closed_websocket_connection_notifications.send(connection_id)
        else
        end
      end

      private def notify_connection_or_identify(kind : String) : Nil
        select
        when @connection_or_identify_notifications.send(kind)
        else
        end
      end

      private def broadcast_event(event_type : String, event_data, category : Int32) : Nil
        frame = JSON.build do |json|
          json.object do
            json.field "op", 5
            json.field "d" do
              json.object do
                json.field "eventType", event_type
                json.field "eventData", event_data
              end
            end
          end
        end

        sockets = @mutex.synchronize do
          @websockets.select { |websocket| (@event_subscriptions[websocket]? || 0_i64) & category != 0 }
        end
        sockets.each do |websocket|
          send_frame(websocket, frame)
        rescue
        end
      end

      private def send_frame(websocket : HTTP::WebSocket, frame : String) : Nil
        @send_mutex.synchronize do
          websocket.send(frame)
        end
      end

      private def identified_frame : String
        JSON.build do |json|
          json.object do
            json.field "op", 2
            json.field "d" do
              json.object do
                json.field "negotiatedRpcVersion", 1
              end
            end
          end
        end
      end

      private def response_frame(request : JSON::Any) : String
        request_type = request["requestType"].as_s
        request_id = request["requestId"].as_s
        data = request["requestData"]?

        result = true
        code = nil.as(Int32?)
        comment = nil
        response_data = nil

        @mutex.synchronize do
          case request_type
          when "GetVersion"
            response_data = JSON.parse({
              "obsVersion"          => "31.0.0",
              "obsWebSocketVersion" => "5.4.0",
            }.to_json)
          when "GetSceneList"
            response_data = scene_list_data
          when "GetCurrentProgramScene"
            response_data = JSON.parse({"currentProgramSceneName" => @current_scene}.to_json)
          when "SetCurrentProgramScene"
            scene_name = data.try(&.["sceneName"].as_s?) || ""
            if @scenes.includes?(scene_name)
              @current_scene = scene_name
            else
              result = false
              comment = "scene not found: #{scene_name}"
            end
          when "GetInputList"
            response_data = input_list_data
          when "GetInputMute"
            if input = find_input(data)
              if input.audio
                response_data = JSON.parse({"inputMuted" => input.muted}.to_json)
              else
                result = false
                code = AUDIO_UNSUPPORTED_CODE
                comment = AUDIO_UNSUPPORTED_COMMENT
              end
            else
              result = false
              comment = "input not found"
            end
          when "SetInputMute"
            if input = find_input(data)
              update_input(input.name, muted: data.try(&.["inputMuted"].as_bool?) || false)
            else
              result = false
              comment = "input not found"
            end
          when "ToggleInputMute"
            if input = find_input(data)
              update_input(input.name, muted: !input.muted)
            else
              result = false
              comment = "input not found"
            end
          when "GetInputVolume"
            if input = find_input(data)
              if input.audio
                response_data = JSON.parse({
                  "inputVolumeMul" => input.volume_mul,
                  "inputVolumeDb"  => input.volume_db,
                }.to_json)
              else
                result = false
                code = AUDIO_UNSUPPORTED_CODE
                comment = AUDIO_UNSUPPORTED_COMMENT
              end
            else
              result = false
              comment = "input not found"
            end
          when "SetInputVolume"
            if input = find_input(data)
              update_input(input.name, volume_mul: data.try(&.["inputVolumeMul"].as_f?) || input.volume_mul)
            else
              result = false
              comment = "input not found"
            end
          when "GetStreamStatus"
            @stream_bytes += @stream_bytes_per_status if @streaming
            response_data = JSON.parse({
              "outputActive"   => @streaming,
              "outputDuration" => (@streaming ? 12_000 : 0),
              "outputBytes"    => @stream_bytes,
            }.to_json)
          when "GetRecordStatus"
            response_data = JSON.parse({
              "outputActive"   => @recording,
              "outputPaused"   => @record_paused,
              "outputTimecode" => (@recording ? "00:00:03.000" : "00:00:00.000"),
              "outputDuration" => (@recording ? 3_000 : 0),
              "outputBytes"    => (@recording ? 4_096 : 0),
            }.to_json)
          when "ToggleStream"
            @streaming = !@streaming
            response_data = JSON.parse({"outputActive" => @streaming}.to_json)
          when "ToggleRecord"
            @recording = !@recording
            @record_paused = false unless @recording
            response_data = JSON.parse({"outputActive" => @recording}.to_json)
          when "StartRecord"
            @recording = true
            @record_paused = false
            response_data = nil
          when "StopRecord"
            @recording = false
            @record_paused = false
            response_data = JSON.parse({"outputPath" => @record_output_path}.to_json)
          when "PauseRecord"
            @record_paused = true
            response_data = nil
          when "ResumeRecord"
            @record_paused = false
            response_data = nil
          when "GetProfileList"
            response_data = JSON.parse({
              "currentProfileName" => @current_profile,
              "profiles"           => @profiles,
            }.to_json)
          when "SetCurrentProfile"
            name = data.try(&.["profileName"]?.try(&.as_s?)) || ""
            if @profiles.includes?(name)
              @current_profile = name
            else
              result = false
              comment = "profile not found"
            end
          when "GetSceneCollectionList"
            response_data = JSON.parse({
              "currentSceneCollectionName" => @current_scene_collection,
              "sceneCollections"           => @scene_collections,
            }.to_json)
          when "SetCurrentSceneCollection"
            name = data.try(&.["sceneCollectionName"]?.try(&.as_s?)) || ""
            if @scene_collections.includes?(name)
              @current_scene_collection = name
            else
              result = false
              comment = "scene collection not found"
            end
          when "GetStats"
            response_data = JSON.parse({
              "cpuUsage"               => 12.5,
              "memoryUsage"            => 512.0,
              "availableDiskSpace"     => 100_000.0,
              "activeFps"              => 59.94,
              "averageFrameRenderTime" => 3.2,
              "renderSkippedFrames"    => 4,
              "renderTotalFrames"      => 10_000,
              "outputSkippedFrames"    => 1,
              "outputTotalFrames"      => 9_999,
            }.to_json)
          else
            result = false
            comment = "unsupported request: #{request_type}"
          end
        end

        JSON.build do |json|
          json.object do
            json.field "op", 7
            json.field "d" do
              json.object do
                json.field "requestType", request_type
                json.field "requestId", request_id
                json.field "requestStatus" do
                  json.object do
                    json.field "result", result
                    json.field "code", code || (result ? 100 : 600)
                    json.field "comment", comment if comment
                  end
                end
                json.field "responseData", response_data if response_data
              end
            end
          end
        end
      end

      private def scene_list_data : JSON::Any
        scenes = @scenes.map_with_index do |scene, index|
          {"sceneIndex" => index, "sceneName" => scene}
        end
        JSON.parse({
          "currentProgramSceneName" => @current_scene,
          "scenes"                  => scenes,
        }.to_json)
      end

      private def input_list_data : JSON::Any
        inputs = @inputs.map do |input|
          {
            "inputName"            => input.name,
            "inputKind"            => input.kind,
            "unversionedInputKind" => input.kind,
          }
        end
        JSON.parse({"inputs" => inputs}.to_json)
      end

      private def find_input(data : JSON::Any?) : AudioInput?
        name = data.try(&.["inputName"].as_s?)
        @inputs.find { |input| input.name == name }
      end

      private def update_input(name : String, muted : Bool? = nil, volume_mul : Float64? = nil) : Nil
        @inputs = @inputs.map do |input|
          next input unless input.name == name

          AudioInput.new(
            input.name,
            input.kind,
            muted.nil? ? input.muted : muted,
            volume_mul || input.volume_mul,
            input.volume_db,
            input.audio
          )
        end
      end
    end
  end
end
