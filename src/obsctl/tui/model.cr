require "../obs/state/obs_snapshot"
require "../runtime/logger"
require "./theme"

module Obsctl
  module TUI
    enum FocusPanel
      Scenes
      Audio
      Profiles
      Collections

      def left : self
        audio? ? Scenes : (collections? ? Profiles : self)
      end

      def right : self
        scenes? ? Audio : (profiles? ? Collections : self)
      end

      def up : self
        profiles? ? Scenes : (collections? ? Audio : self)
      end

      def down : self
        scenes? ? Profiles : (audio? ? Collections : self)
      end
    end

    enum View
      Main
      Settings
    end

    struct AnimClock
      property frame : UInt64

      def initialize(@frame = 0_u64)
      end

      def tick
        @frame &+= 1
      end
    end

    record LogEntry,
      level : Runtime::LogLevel,
      message : String,
      code : String? = nil,
      timestamp : Time = Time.utc

    class CommandPaletteState
      property active : Bool
      property input : String
      property completions : Array(String)
      property completion_index : Int32?

      def initialize(@active = false, @input = "", @completions = [] of String, @completion_index = nil)
      end

      def cycle_next
        return if @completions.empty?
        @completion_index = @completion_index ? (@completion_index.not_nil! + 1) % @completions.size : 0
        @input = @completions[@completion_index.not_nil!]
      end

      def cycle_previous
        return if @completions.empty?
        @completion_index = case index = @completion_index
                            when Nil then @completions.size - 1
                            when 0   then @completions.size - 1
                            else          index - 1
                            end
        @input = @completions[@completion_index.not_nil!]
      end
    end

    class Model
      MAX_LOG_ENTRIES = 200

      property snapshot : OBS::State::ObsSnapshot?
      property logs : Array(LogEntry)
      property command_palette : CommandPaletteState
      property last_result : String?
      property last_result_frame : UInt64
      property connected_to_daemon : Bool
      property focus : FocusPanel
      property scene_cursor : Int32
      property audio_cursor : Int32
      property profile_cursor : Int32
      property collection_cursor : Int32
      property profiles : Array(String)
      property current_profile : String?
      property scene_collections : Array(String)
      property current_scene_collection : String?
      property meter_levels : Hash(String, Float64)
      property anim : AnimClock
      property scene_flash : Tuple(String, UInt64)?
      property view : View
      property theme : Theme
      property show_icons : Bool
      property advanced_ui : Bool

      def initialize(@theme = Theme.default, @show_icons = true, @advanced_ui = true)
        @snapshot = nil
        @logs = [] of LogEntry
        @command_palette = CommandPaletteState.new
        @last_result = nil
        @last_result_frame = 0_u64
        @connected_to_daemon = false
        @focus = FocusPanel::Scenes
        @scene_cursor = 0
        @audio_cursor = 0
        @profile_cursor = 0
        @collection_cursor = 0
        @profiles = [] of String
        @current_profile = nil
        @scene_collections = [] of String
        @current_scene_collection = nil
        @meter_levels = {} of String => Float64
        @anim = AnimClock.new
        @scene_flash = nil
        @view = View::Main
      end

      def rich_ui? : Bool
        @show_icons && @advanced_ui
      end

      def symbol(rich : String, fallback : String) : String
        rich_ui? ? rich : fallback
      end

      def scenes : Array(OBS::State::SceneState)
        @snapshot.try(&.scenes) || [] of OBS::State::SceneState
      end

      def audio_inputs : Array(OBS::State::AudioState)
        @snapshot.try(&.audio_inputs) || [] of OBS::State::AudioState
      end

      def current_scene : String?
        @snapshot.try(&.current_scene)
      end

      def obs_connected? : Bool
        @snapshot.try(&.connected) || false
      end

      def streaming? : Bool
        @snapshot.try(&.output.streaming) || false
      end

      def recording? : Bool
        @snapshot.try(&.output.recording) || false
      end

      def push_log(entry : LogEntry)
        @logs << entry
        @logs.shift(@logs.size - MAX_LOG_ENTRIES) if @logs.size > MAX_LOG_ENTRIES
      end

      def set_last_result(message : String)
        @last_result = message
        @last_result_frame = @anim.frame
      end

      def revealed_last_result(characters_per_frame : Int32) : String?
        result = @last_result
        return nil unless result
        elapsed = (@anim.frame - @last_result_frame).to_i64
        result.each_grapheme.first(elapsed * characters_per_frame.clamp(1, Int32::MAX)).join
      end

      def move_up
        case @focus
        when .scenes?      then @scene_cursor = {@scene_cursor - 1, 0}.max
        when .audio?       then @audio_cursor = {@audio_cursor - 1, 0}.max
        when .profiles?    then @profile_cursor = {@profile_cursor - 1, 0}.max
        when .collections? then @collection_cursor = {@collection_cursor - 1, 0}.max
        end
      end

      def move_down
        case @focus
        when .scenes?      then @scene_cursor = {@scene_cursor + 1, scenes.size - 1}.min.clamp(0, Int32::MAX)
        when .audio?       then @audio_cursor = {@audio_cursor + 1, audio_inputs.size - 1}.min.clamp(0, Int32::MAX)
        when .profiles?    then @profile_cursor = {@profile_cursor + 1, @profiles.size - 1}.min.clamp(0, Int32::MAX)
        when .collections? then @collection_cursor = {@collection_cursor + 1, @scene_collections.size - 1}.min.clamp(0, Int32::MAX)
        end
      end

      def clamp_cursors
        @scene_cursor = @scene_cursor.clamp(0, {scenes.size - 1, 0}.max)
        @audio_cursor = @audio_cursor.clamp(0, {audio_inputs.size - 1, 0}.max)
        @profile_cursor = @profile_cursor.clamp(0, {@profiles.size - 1, 0}.max)
        @collection_cursor = @collection_cursor.clamp(0, {@scene_collections.size - 1, 0}.max)
      end

      def focused_scene : OBS::State::SceneState?
        scenes[@scene_cursor]?
      end

      def focused_audio : OBS::State::AudioState?
        audio_inputs[@audio_cursor]?
      end
    end
  end
end
