require "json"
require "./transport"
require "./protocol/response"
require "./protocol/event"
require "./protocol/event_subscription"
require "./requests/version"
require "./requests/scenes"
require "./requests/audio"
require "./requests/outputs"
require "./requests/studio"
require "./state/obs_snapshot"
require "./state/record_status"
require "../config/config"
require "../domain/errors"
require "../domain/aliases"

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
        request(Requests::Version::GET_VERSION).response_data || JSON.parse("{}")
      end

      # Returns the current OBS scene names in OBS order.
      def scene_names : Array(String)
        data = request(Requests::Scenes::GET_SCENE_LIST).response_data || JSON.parse("{}")
        data["scenes"].as_a.map(&.["sceneName"].as_s)
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
        data["inputs"].as_a.map(&.["inputName"].as_s)
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

      def output_state : State::OutputState
        output_details[:state]
      end

      def toggle_stream : Bool?
        data = request(Requests::Outputs::TOGGLE_STREAM).response_data || JSON.parse("{}")
        data["outputActive"]?.try(&.as_bool?)
      end

      def toggle_record : Bool?
        data = request(Requests::Outputs::TOGGLE_RECORD).response_data || JSON.parse("{}")
        data["outputActive"]?.try(&.as_bool?)
      end

      # Starts recording. OBS returns no data, so the caller re-reads status.
      def start_record : Nil
        request(Requests::Outputs::START_RECORD)
      end

      # Stops recording and returns the written file path when OBS reports one.
      def stop_record : String?
        data = request(Requests::Outputs::STOP_RECORD).response_data || JSON.parse("{}")
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
        data = request(Requests::Outputs::GET_RECORD_STATUS).response_data || JSON.parse("{}")
        active = data["outputActive"]?.try(&.as_bool?)
        State::RecordStatus.new(
          active: active,
          paused: data["outputPaused"]?.try(&.as_bool?),
          timecode: data["outputTimecode"]?.try(&.as_s?),
          duration_ms: active == true ? data["outputDuration"]?.try(&.as_i64?) : nil,
          bytes: active == true ? data["outputBytes"]?.try(&.as_i64?) : nil
        )
      end

      def profiles : NamedTuple(current: String?, names: Array(String))
        data = request(Requests::Studio::GET_PROFILE_LIST).response_data || JSON.parse("{}")
        entries = data["profiles"]?.try(&.as_a?) || [] of JSON::Any
        names = entries.compact_map do |profile|
          profile.as_s? || profile.as_h?.try { profile["profileName"]?.try(&.as_s?) }
        end
        {current: data["currentProfileName"]?.try(&.as_s?), names: names}
      end

      def set_profile(name : String) : Nil
        request(Requests::Studio::SET_CURRENT_PROFILE, Requests::Studio.profile(name))
      end

      def scene_collections : NamedTuple(current: String?, names: Array(String))
        data = request(Requests::Studio::GET_SCENE_COLLECTION_LIST).response_data || JSON.parse("{}")
        names = data["sceneCollections"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
        {current: data["currentSceneCollectionName"]?.try(&.as_s?), names: names}
      end

      def set_scene_collection(name : String) : Nil
        request(Requests::Studio::SET_SCENE_COLLECTION, Requests::Studio.scene_collection(name))
      end

      def stats : State::ObsStats
        data = request(Requests::Studio::GET_STATS).response_data || JSON.parse("{}")
        State::ObsStats.from_response(data)
      end

      # Fetches the performance and output counters used by the daemon's
      # periodic telemetry poller. OBS exposes bytes rather than bitrate, so
      # the supervisor derives kbit/s from consecutive samples.
      def telemetry_sample : TelemetrySample
        stream = request(Requests::Outputs::GET_STREAM_STATUS).response_data || JSON.parse("{}")
        record = request(Requests::Outputs::GET_RECORD_STATUS).response_data || JSON.parse("{}")
        stream_active = stream["outputActive"]?.try(&.as_bool?) || false
        record_active = record["outputActive"]?.try(&.as_bool?) || false
        TelemetrySample.new(
          stats: stats,
          stream_active: stream_active,
          record_active: record_active,
          stream_bytes: stream["outputBytes"]?.try(&.as_i64?),
          stream_duration_ms: stream_active ? stream["outputDuration"]?.try(&.as_i64?) : nil,
          record_duration_ms: record_active ? record["outputDuration"]?.try(&.as_i64?) : nil
        )
      end

      # Fetches only the scene list and current scene for targeted state updates.
      def scene_snapshot : {current_scene: String?, scenes: Array(State::SceneState)}
        current = current_scene
        scenes = scene_names.map do |name|
          configured = @config.scenes.find { |scene| scene.name == name }
          State::SceneState.new(
            name: name,
            alias: configured.try(&.alias),
            shortcut: configured.try(&.shortcut),
            group: configured.try(&.group),
            active: current == name,
            hidden: configured.try(&.hidden) || false
          )
        end
        {current_scene: current, scenes: scenes}
      end

      # Fetches only the audio input list for targeted state updates.
      def audio_snapshot : Array(State::AudioState)
        input_names.compact_map { |name| audio_state_for(name) }
      end

      # Reads one input's audio state, or nil when OBS will not report it.
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
      private def audio_state_for(name : String) : State::AudioState?
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
      rescue Domain::ObsRequestFailed
        nil
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
            active: current == name,
            hidden: configured.try(&.hidden) || false
          )
        end
        audio = input_names.compact_map { |name| audio_state_for(name) }
        profile_data = profiles
        collection_data = scene_collections
        output = output_details
        State::ObsSnapshot.new(
          connected: true,
          obs_studio_version: version_data["obsVersion"]?.try(&.as_s),
          obs_websocket_version: version_data["obsWebSocketVersion"]?.try(&.as_s),
          current_scene: current,
          scenes: scenes,
          audio_inputs: audio,
          output: output[:state],
          profiles: profile_data[:names],
          current_profile: profile_data[:current],
          scene_collections: collection_data[:names],
          current_scene_collection: collection_data[:current],
          stats: stats,
          stream_duration_ms: output[:stream_duration_ms],
          record_duration_ms: output[:record_duration_ms]
        )
      end

      private def output_details
        stream = request(Requests::Outputs::GET_STREAM_STATUS).response_data || JSON.parse("{}")
        record = request(Requests::Outputs::GET_RECORD_STATUS).response_data || JSON.parse("{}")
        {
          state: State::OutputState.new(
            streaming: stream["outputActive"]?.try(&.as_bool?),
            recording: record["outputActive"]?.try(&.as_bool?)
          ),
          stream_duration_ms: stream["outputActive"]?.try(&.as_bool?) == true ? stream["outputDuration"]?.try(&.as_i64?) : nil,
          record_duration_ms: record["outputActive"]?.try(&.as_bool?) == true ? record["outputDuration"]?.try(&.as_i64?) : nil,
        }
      end

      private def number(data : JSON::Any, key : String) : Float64?
        value = data[key]?
        return unless value
        value.as_f? || value.as_i?.try(&.to_f64)
      end
    end
  end
end
