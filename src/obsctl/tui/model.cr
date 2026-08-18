require "../obs/state/obs_snapshot"
require "../runtime/logger"
require "./theme"
require "./anim"
require "./meter"
require "./localization"
require "./scene_picker"

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

      def pulse(period_ticks : UInt64) : Float32
        period = {period_ticks, 1_u64}.max
        phase = (@frame % period).to_f32 / period.to_f32
        Math.sin(phase * Math::TAU.to_f32) * 0.5_f32 + 0.5_f32
      end

      def spinner(frames : Indexable(String), ticks_per_frame : UInt64 = 1_u64) : String
        return "" if frames.empty?
        step = {ticks_per_frame, 1_u64}.max
        frames[((@frame // step) % frames.size).to_i]
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
        index = @completion_index
        next_index = index ? (index + 1) % @completions.size : 0
        @completion_index = next_index
        @input = @completions[next_index]
      end

      def cycle_previous
        return if @completions.empty?
        next_index = case index = @completion_index
                     when Nil then @completions.size - 1
                     when 0   then @completions.size - 1
                     else          index - 1
                     end
        @completion_index = next_index
        @input = @completions[next_index]
      end
    end

    class Model
      MAX_LOG_ENTRIES = 200

      # How many samples each sparkline keeps. The stats widgets plot these at
      # one column per sample, so this is also the widest a sparkline can be
      # before it starts repeating; 32 covers the panel at any usable terminal
      # width without holding history nothing draws.
      METRIC_HISTORY_SAMPLES = 32

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
      property meter_levels : Hash(String, Float64)
      # The highest point each meter has reached and the frame it reached it
      # on. Storing the frame rather than decaying the value every tick keeps
      # the peak marker a pure function of the clock, so nothing has to run
      # between renders for it to fall.
      property meter_peaks : Hash(String, Tuple(Float64, UInt64))
      property cpu_history : Array(Float64)
      property bitrate_history : Array(Float64)
      property fps_history : Array(Float64)
      property anim : AnimClock
      property scene_flash : Tuple(String, UInt64)?
      property view : View
      property theme : Theme
      property show_icons : Bool
      property advanced_ui : Bool
      property command_palette_prefix : String
      property locale : String
      property settings_cursor : Int32
      property theme_preview_origin : Theme?
      # Keys of a multi-key binding pressed so far, e.g. `<leader>f`. Non-empty
      # means the which-key menu is open and the next key completes or cancels.
      property pending_sequence : String
      # True while the scene picker overlay is open, during which it captures
      # every key.
      property scene_picker_active : Bool
      # The picker keeps its own cursor rather than borrowing `scene_cursor`,
      # so opening it does not move the dashboard's selection out from under
      # whichever panel is focused, and closing it without picking leaves the
      # dashboard exactly as it was.
      property scene_picker_cursor : Int32

      def initialize(@theme = Theme.default, @show_icons = true, @advanced_ui = true, @command_palette_prefix = "/", @locale = "en")
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
        @meter_levels = {} of String => Float64
        @meter_peaks = {} of String => Tuple(Float64, UInt64)
        @cpu_history = [] of Float64
        @bitrate_history = [] of Float64
        @fps_history = [] of Float64
        @anim = AnimClock.new
        @scene_flash = nil
        @view = View::Main
        @settings_cursor = 0
        @theme_preview_origin = nil
        @pending_sequence = ""
        @scene_picker_active = false
        @scene_picker_cursor = 0
      end

      # The scene picker's rows, rebuilt from the current scenes on every call
      # rather than stored.
      #
      # Input resolution, the widget and the hit test all ask for them; a
      # stored copy could disagree with the scene list after an OBS event lands
      # mid-frame, which would point a label at the wrong scene.
      def scene_picker_entries : Array(ScenePicker::Entry)
        ScenePicker.entries(scenes)
      end

      def rich_ui? : Bool
        @show_icons && @advanced_ui
      end

      def symbol(rich : String, fallback : String) : String
        rich_ui? ? rich : fallback
      end

      def scenes : Array(OBS::State::SceneState)
        @snapshot.try(&.scenes.reject(&.hidden)) || [] of OBS::State::SceneState
      end

      def audio_inputs : Array(OBS::State::AudioState)
        @snapshot.try(&.audio_inputs) || [] of OBS::State::AudioState
      end

      def profiles : Array(String)
        @snapshot.try(&.profiles) || [] of String
      end

      def current_profile : String?
        @snapshot.try(&.current_profile)
      end

      def scene_collections : Array(String)
        @snapshot.try(&.scene_collections) || [] of String
      end

      def current_scene_collection : String?
        @snapshot.try(&.current_scene_collection)
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

      def stats : OBS::State::ObsStats?
        @snapshot.try(&.stats)
      end

      def stream_bitrate_kbps : Float64?
        @snapshot.try(&.stream_bitrate_kbps)
      end

      def stream_duration_ms : Int64?
        @snapshot.try(&.stream_duration_ms)
      end

      def record_duration_ms : Int64?
        @snapshot.try(&.record_duration_ms)
      end

      # Appends this frame's readings to the sparkline histories.
      #
      # Each series is sampled only when the snapshot actually carries it: a
      # snapshot with no stats must not push a zero, because a zero is a real
      # reading that would draw as a trough in the graph rather than as the
      # absence of data it really is.
      def record_metric_sample
        if current_stats = stats
          append_metric(@cpu_history, current_stats.cpu_usage_percent)
          append_metric(@fps_history, current_stats.active_fps)
        end
        if bitrate = stream_bitrate_kbps
          append_metric(@bitrate_history, bitrate)
        end
      end

      # Adds one reading and drops whatever has scrolled off the left edge.
      #
      # The trim lives here rather than in `record_metric_sample` so the bound
      # holds for every series by construction; it used to be a separate pass
      # over all three arrays afterwards, which is a rule that only holds as
      # long as someone remembers to add the next series to that list.
      private def append_metric(history : Array(Float64), value : Float64) : Nil
        history << value
        history.shift(history.size - METRIC_HISTORY_SAMPLES) if history.size > METRIC_HISTORY_SAMPLES
      end

      # Applies an optimistic volume value so rapid keyboard changes render
      # immediately while the debounced OBS command is still pending.
      def preview_audio_volume(input_name : String, percent : Int32) : Nil
        snapshot = @snapshot
        return unless snapshot

        bounded = percent.clamp(0, 100)
        inputs = snapshot.audio_inputs.map do |input|
          next input unless input.name == input_name
          input.copy_with(
            volume_mul: bounded.to_f64 / 100.0,
            volume_percent: bounded
          )
        end
        @snapshot = snapshot.copy_with(audio_inputs: inputs)
      end

      # Records a meter reading and raises the peak hold when the reading beats
      # whatever is left of the last one.
      def record_meter_level(input_name : String, level : Float64) : Nil
        @meter_levels[input_name] = level
        fraction = Meter.fraction(level)
        held = meter_peak(input_name)
        @meter_peaks[input_name] = {fraction, @anim.frame} if held.nil? || fraction >= held
      end

      # How far up the meter the peak marker has fallen to by now, or nil once
      # it has slid all the way back to the floor.
      def meter_peak(input_name : String) : Float64?
        peak = @meter_peaks[input_name]?
        return unless peak
        remaining = peak[0] - (@anim.frame - peak[1]).to_f64 * Meter::PEAK_FALL_PER_FRAME
        remaining > 0.0 ? remaining : nil
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
        return unless result
        elapsed = (@anim.frame - @last_result_frame).to_i64
        result.each_grapheme.first(elapsed * characters_per_frame.clamp(1, Int32::MAX)).join
      end

      def move_up
        move_by(-1)
      end

      def move_down
        move_by(1)
      end

      def move_by(delta : Int32)
        move_to(cursor + delta)
      end

      def move_top
        move_to(0)
      end

      def move_bottom
        move_to(item_count - 1)
      end

      # Cursor moves are clamped rather than wrapped: `G` on the last item and
      # a half page past the end both stop at the end, the way they do in vim.
      def move_to(index : Int32)
        bounded = index.clamp(0, {item_count - 1, 0}.max)
        case @focus
        when .scenes?      then @scene_cursor = bounded
        when .audio?       then @audio_cursor = bounded
        when .profiles?    then @profile_cursor = bounded
        when .collections? then @collection_cursor = bounded
        end
      end

      def cursor(panel : FocusPanel = @focus) : Int32
        case panel
        when .scenes?   then @scene_cursor
        when .audio?    then @audio_cursor
        when .profiles? then @profile_cursor
        else                 @collection_cursor
        end
      end

      def item_count(panel : FocusPanel = @focus) : Int32
        case panel
        when .scenes?   then scenes.size
        when .audio?    then audio_inputs.size
        when .profiles? then profiles.size
        else                 scene_collections.size
        end
      end

      def clamp_cursors
        @scene_cursor = @scene_cursor.clamp(0, {scenes.size - 1, 0}.max)
        @audio_cursor = @audio_cursor.clamp(0, {audio_inputs.size - 1, 0}.max)
        @profile_cursor = @profile_cursor.clamp(0, {profiles.size - 1, 0}.max)
        @collection_cursor = @collection_cursor.clamp(0, {scene_collections.size - 1, 0}.max)
        @scene_picker_cursor = @scene_picker_cursor.clamp(0, {scenes.size - 1, 0}.max)
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
