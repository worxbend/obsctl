require "json"
require "./transport"
require "./protocol/json_value"
require "./protocol/response"
require "./protocol/event"
require "./protocol/event_subscription"
require "./requests/version"
require "./requests/scenes"
require "./requests/audio"
require "./requests/outputs"
require "./requests/studio"
require "./state/obs_stats"
require "./state/output_state"
require "./state/record_status"
require "../config/config"
require "../domain/errors"
require "../domain/volume"

module Obsctl
  module OBS
    record TelemetrySample,
      stats : State::ObsStats,
      stream_active : Bool,
      record_active : Bool,
      stream_bytes : Int64?,
      stream_duration_ms : Int64?,
      record_duration_ms : Int64?

    # obs-websocket 5.x client used by the server-owned OBS supervisor.
    #
    # Every method below is one OBS operation expressed in obsctl's terms: it
    # sends a request, reads the fields it needs out of the answer, and returns
    # a typed value. The connection underneath — handshake, framing, request
    # correlation, disconnect handling — belongs to `Transport`, and the
    # forwarding methods at the top are the whole of what callers need from it.
    class Client
      # Kept as a class constant because it is part of this class's documented
      # behaviour; `Transport` owns the buffer itself.
      EVENT_BUFFER_SIZE = Transport::EVENT_BUFFER_SIZE
      private EMPTY_OBJECT      = JSON::Any.new({} of String => JSON::Any)

      def initialize(
        @config : Config::Config,
        event_subscriptions : Int32? = nil,
      )
        @transport = Transport.new(@config, event_subscriptions)
      end

      # Channel of parsed OBS events from opcode 5 frames.
      def events : Channel(Protocol::Event)
        @transport.events
      end

      # Opens the WebSocket and performs Hello/Identify/Identified.
      def connect : Nil
        @transport.connect
      end

      # Closes the WebSocket and marks this client as no longer identified.
      def close : Nil
        @transport.close
      end

      # Returns true after Identify completes and the underlying socket is open.
      def connected? : Bool
        @transport.connected?
      end

      # Returns true once `connect` has opened the socket, whether or not the
      # Hello/Identify handshake that follows it succeeded.
      def socket_open? : Bool
        @transport.socket_open?
      end

      # Returns the safe terminal connection error that closed this client.
      def terminal_error : Domain::ConnectionFailed?
        @transport.terminal_error
      end

      # Waits for the reader to observe a terminal close or protocol error.
      def wait_for_close(timeout : Time::Span) : Domain::ConnectionFailed?
        @transport.wait_for_close(timeout)
      end

      # Sends a typed obs-websocket request and waits for its response.
      def request(request_type : String, data : JSON::Any? = nil) : Protocol::Response
        @transport.request(request_type, data)
      end

      # Fetches OBS and obs-websocket version metadata.
      def version : JSON::Any
        response_data(Requests::Version::GET_VERSION)
      end

      # Returns the current OBS scene names in OBS order.
      def scene_names : Array(String)
        data = response_data(Requests::Scenes::GET_SCENE_LIST)
        data["scenes"].as_a.map(&.["sceneName"].as_s)
      end

      # Returns the current OBS program scene name when available.
      def current_scene : String?
        data = response_data(Requests::Scenes::GET_CURRENT_PROGRAM_SCENE)
        data["currentProgramSceneName"]?.try(&.as_s)
      end

      # Changes the current OBS program scene by exact OBS scene name.
      def set_scene(name : String) : Nil
        request(Requests::Scenes::SET_CURRENT_PROGRAM_SCENE, Requests::Scenes.set_current_program_scene(name))
      end

      # Returns current OBS input names.
      def input_names : Array(String)
        data = response_data(Requests::Audio::GET_INPUT_LIST)
        data["inputs"].as_a.map(&.["inputName"].as_s)
      end

      # Returns mute state for an OBS input by exact OBS input name.
      def input_muted(name : String) : Bool?
        data = response_data(Requests::Audio::GET_INPUT_MUTE, Requests::Audio.input_name(name))
        data["inputMuted"]?.try(&.as_bool)
      end

      # Returns OBS input volume in multiplier, dB, and user-facing percent.
      def input_volume(name : String) : NamedTuple(mul: Float64?, db: Float64?, percent: Int32?)
        data = response_data(Requests::Audio::GET_INPUT_VOLUME, Requests::Audio.input_name(name))
        mul = number(data, "inputVolumeMul")
        db = number(data, "inputVolumeDb")
        percent = mul.try { |value| Domain::Volume.mul_to_percent(value) }
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
        request(Requests::Audio::SET_INPUT_VOLUME, Requests::Audio.set_volume(name, Domain::Volume.percent_to_mul(percent)))
      end

      def output_state : State::OutputState
        output_details[:state]
      end

      def toggle_stream : Bool?
        data = response_data(Requests::Outputs::TOGGLE_STREAM)
        data["outputActive"]?.try(&.as_bool?)
      end

      def toggle_record : Bool?
        data = response_data(Requests::Outputs::TOGGLE_RECORD)
        data["outputActive"]?.try(&.as_bool?)
      end

      # Starts recording. OBS returns no data, so the caller re-reads status.
      def start_record : Nil
        request(Requests::Outputs::START_RECORD)
      end

      # Stops recording and returns the written file path when OBS reports one.
      def stop_record : String?
        data = response_data(Requests::Outputs::STOP_RECORD)
        data["outputPath"]?.try(&.as_s?)
      end

      def pause_record : Nil
        request(Requests::Outputs::PAUSE_RECORD)
      end

      def resume_record : Nil
        request(Requests::Outputs::RESUME_RECORD)
      end

      # Returns the full record status, including pause state and timecode.
      def record_status : State::RecordStatus
        data = response_data(Requests::Outputs::GET_RECORD_STATUS)
        active = output_active(data)
        State::RecordStatus.new(
          active: active,
          paused: data["outputPaused"]?.try(&.as_bool?),
          timecode: data["outputTimecode"]?.try(&.as_s?),
          duration_ms: output_value_while_active(data, "outputDuration", active),
          bytes: output_value_while_active(data, "outputBytes", active)
        )
      end

      def profiles : NamedTuple(current: String?, names: Array(String))
        data = response_data(Requests::Studio::GET_PROFILE_LIST)
        {current: data["currentProfileName"]?.try(&.as_s?), names: profile_names(data["profiles"]?.try(&.as_a?))}
      end

      def set_profile(name : String) : Nil
        request(Requests::Studio::SET_CURRENT_PROFILE, Requests::Studio.profile(name))
      end

      def scene_collections : NamedTuple(current: String?, names: Array(String))
        data = response_data(Requests::Studio::GET_SCENE_COLLECTION_LIST)
        {current: data["currentSceneCollectionName"]?.try(&.as_s?), names: string_list(data, "sceneCollections")}
      end

      def set_scene_collection(name : String) : Nil
        request(Requests::Studio::SET_SCENE_COLLECTION, Requests::Studio.scene_collection(name))
      end

      def stats : State::ObsStats
        data = response_data(Requests::Studio::GET_STATS)
        State::ObsStats.from_response(data)
      end

      # Fetches the performance and output counters used by the daemon's
      # periodic telemetry poller. OBS exposes bytes rather than bitrate, so
      # the supervisor derives kbit/s from consecutive samples.
      def telemetry_sample : TelemetrySample
        stream, record = output_statuses
        stream_active = output_active(stream) || false
        record_active = output_active(record) || false
        TelemetrySample.new(
          stats: stats,
          stream_active: stream_active,
          record_active: record_active,
          stream_bytes: stream["outputBytes"]?.try(&.as_i64?),
          stream_duration_ms: output_value_while_active(stream, "outputDuration", stream_active),
          record_duration_ms: output_value_while_active(record, "outputDuration", record_active)
        )
      end

      # Reads the scene list and the current scene together, which is what a
      # snapshot needs and what `SceneListChanged` invalidates in one go.
      def scene_readings : {current_scene: String?, scene_names: Array(String)}
        {current_scene: current_scene, scene_names: scene_names}
      end

      # Reads one input's mute and volume, or nil when OBS will not report them.
      #
      # `GetInputList` returns every input, not only the audible ones: image,
      # color, and silent browser sources are all in there, and OBS answers a
      # mute or volume read on them with "The specified input does not support
      # audio." Letting that escape fails the whole snapshot, which the
      # supervisor reads as a lost connection — so a single non-audio source in
      # the scene collection put the daemon in an endless reconnect loop and
      # left it permanently unusable.
      #
      # Any per-input read failure is treated the same way. An input OBS will
      # not describe is one obsctl cannot control, and dropping it from the
      # audio matrix is always better than dropping the OBS connection.
      def audio_readings(name : String) : NamedTuple(muted: Bool?, volume: NamedTuple(mul: Float64?, db: Float64?, percent: Int32?))?
        {muted: input_muted(name), volume: input_volume(name)}
      rescue Domain::ObsRequestFailed
        nil
      end

      # Reads stream and record status in one pass, since the two output flags
      # and the two durations all come from the same pair of requests.
      def output_details
        stream, record = output_statuses
        stream_active = output_active(stream)
        record_active = output_active(record)
        {
          state: State::OutputState.new(
            streaming: stream_active,
            recording: record_active
          ),
          stream_duration_ms: output_value_while_active(stream, "outputDuration", stream_active),
          record_duration_ms: output_value_while_active(record, "outputDuration", record_active),
        }
      end

      # Sends a request and returns its response body, or an empty object when
      # OBS answered without one.
      #
      # OBS omits `responseData` entirely for requests that have nothing to
      # say — `StartRecord` is one — and it is allowed to leave out an
      # individual field of a body it does send. Falling back to an empty
      # object means every reader below can ask for its fields the same way
      # and get nil for what is not there, instead of each one guarding
      # against a missing body first.
      private def response_data(request_type : String, data : JSON::Any? = nil) : JSON::Any
        request(request_type, data).response_data || EMPTY_OBJECT
      end

      private def number(data : JSON::Any, key : String) : Float64?
        Protocol::JsonValue.number(data, key)
      end

      private def output_statuses : Tuple(JSON::Any, JSON::Any)
        {
          response_data(Requests::Outputs::GET_STREAM_STATUS),
          response_data(Requests::Outputs::GET_RECORD_STATUS),
        }
      end

      private def output_active(data : JSON::Any) : Bool?
        data["outputActive"]?.try(&.as_bool?)
      end

      private def output_value_while_active(data : JSON::Any, key : String, active : Bool?) : Int64?
        active == true ? data[key]?.try(&.as_i64?) : nil
      end

      private def profile_names(entries : Array(JSON::Any)?) : Array(String)
        (entries || [] of JSON::Any).compact_map do |profile|
          profile.as_s? || profile.as_h?.try { profile["profileName"]?.try(&.as_s?) }
        end
      end

      private def string_list(data : JSON::Any, key : String) : Array(String)
        data[key]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      end
    end
  end
end
