require "http/server"
require "http/web_socket"
require "json"
require "../../src/obsctl/config/config"

module Obsctl
  module SpecSupport
    class FakeObsServer
      record AudioInput,
        name : String,
        kind : String = "input",
        muted : Bool = false,
        volume_mul : Float64 = 1.0,
        volume_db : Float64 = 0.0

      getter host : String
      getter port : Int32

      @server : HTTP::Server
      @mutex = Mutex.new
      @identify_data = nil.as(JSON::Any?)
      @request_notifications = Channel(String).new(16)
      @websockets = [] of HTTP::WebSocket

      def initialize(
        @scenes : Array(String) = ["Main Camera", "Screen Share", "BRB"],
        @current_scene : String = "Main Camera",
        @inputs : Array(AudioInput) = [
          AudioInput.new("Mic/Aux", "input", false, 0.7, -3.0),
          AudioInput.new("Desktop Audio", "output", true, 0.4, -8.0),
        ],
        @request_delays : Hash(String, Time::Span) = {} of String => Time::Span,
        @request_timeout_ms : Int32 = 500,
      )
        @host = "127.0.0.1"
        @server = HTTP::Server.new([websocket_handler])
        address = @server.bind_tcp(@host, 0)
        @port = address.port
      end

      def start : self
        spawn(name: "fake-obs-websocket") { @server.listen }
        Fiber.yield
        self
      end

      def stop : Nil
        @server.close
        sockets = @mutex.synchronize do
          existing = @websockets.dup
          @websockets.clear
          existing
        end
        sockets.each do |websocket|
          websocket.close
        rescue
        end
      rescue
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

      def identify_data : JSON::Any?
        @mutex.synchronize { @identify_data }
      end

      def next_request(timeout : Time::Span = 1.second) : String?
        select
        when request_type = @request_notifications.receive
          request_type
        when timeout(timeout)
          nil
        end
      end

      private def websocket_handler : HTTP::WebSocketHandler
        HTTP::WebSocketHandler.new do |websocket, _context|
          @mutex.synchronize { @websockets << websocket }
          websocket.on_close do
            @mutex.synchronize { @websockets.delete(websocket) }
          end
          websocket.send(hello_frame)
          websocket.on_message do |message|
            handle_message(websocket, message)
          end
        end
      end

      private def handle_message(websocket : HTTP::WebSocket, message : String) : Nil
        frame = JSON.parse(message)
        case frame["op"].as_i
        when 1
          @mutex.synchronize { @identify_data = frame["d"] }
          websocket.send(identified_frame)
        when 6
          request = frame["d"]
          request_type = request["requestType"].as_s
          notify_request(request_type)
          if delay = @request_delays[request_type]?
            sleep delay
          end
          websocket.send(response_frame(request))
        end
      end

      private def hello_frame : String
        JSON.build do |json|
          json.object do
            json.field "op", 0
            json.field "d" do
              json.object do
                json.field "obsWebSocketVersion", "5.4.0"
                json.field "rpcVersion", 1
              end
            end
          end
        end
      end

      private def notify_request(request_type : String) : Nil
        select
        when @request_notifications.send(request_type)
        else
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
              response_data = JSON.parse({"inputMuted" => input.muted}.to_json)
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
              response_data = JSON.parse({
                "inputVolumeMul" => input.volume_mul,
                "inputVolumeDb"  => input.volume_db,
              }.to_json)
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
                    json.field "code", result ? 100 : 600
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
            input.volume_db
          )
        end
      end
    end
  end
end
