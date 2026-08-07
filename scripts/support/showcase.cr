require "../../src/obsctl/tui/widgets/dashboard"

# The state the generated frames are rendered from.
#
# The microsite frames and the README screenshots are both produced from the
# real widget code, and both need a dashboard that is doing something rather
# than an empty shell. Keeping the model here means the two cannot drift into
# showing different streams.
module Showcase
  extend self

  # The 16 ANSI colours, for the one built-in theme that uses indexed colours.
  INDEXED = {
    0 => "#1c1c1c", 1 => "#d64545", 2 => "#4fb477", 3 => "#d6a544",
    4 => "#4f8ed6", 5 => "#b46fd6", 6 => "#4fc3d6", 7 => "#c8c8c8",
    8 => "#6a6a6a", 9 => "#ff6b6b", 10 => "#6fe3a0", 11 => "#ffd166",
    12 => "#6fb2ff", 13 => "#d29bff", 14 => "#6fe6ff", 15 => "#f5f5f5",
  }

  # Builds a model holding the state a busy stream would actually be in, so the
  # frame shows every panel doing something rather than an empty shell.
  def model(theme : Obsctl::TUI::Theme) : Obsctl::TUI::Model
    model = Obsctl::TUI::Model.new(theme: theme)
    model.connected_to_daemon = true
    model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
      connected: true,
      obs_studio_version: "31.0.0",
      obs_websocket_version: "5.5.0",
      current_scene: "Main Camera",
      scenes: [
        Obsctl::OBS::State::SceneState.new("Main Camera", alias: "main", shortcut: "1", group: "Live", active: true),
        Obsctl::OBS::State::SceneState.new("Screen Share", alias: "screen", shortcut: "2", group: "Live"),
        Obsctl::OBS::State::SceneState.new("Guest Cam", alias: "guest", shortcut: "3", group: "Live"),
        Obsctl::OBS::State::SceneState.new("BRB", alias: "brb", shortcut: "4", group: "Breaks"),
        Obsctl::OBS::State::SceneState.new("Starting Soon", alias: "soon", shortcut: "5", group: "Breaks"),
      ],
      audio_inputs: [
        Obsctl::OBS::State::AudioState.new("Mic/Aux", alias: "mic", shortcut: "m", muted: false, volume_mul: 0.72, volume_db: -4.2, volume_percent: 72),
        Obsctl::OBS::State::AudioState.new("Desktop Audio", alias: "desktop", shortcut: "d", muted: false, volume_mul: 0.48, volume_db: -8.1, volume_percent: 48),
        Obsctl::OBS::State::AudioState.new("Guest Line", alias: "guest", muted: true, volume_mul: 0.6, volume_db: -6.0, volume_percent: 60),
      ],
      output: Obsctl::OBS::State::OutputState.new(streaming: true, recording: true),
      profiles: ["Default", "Streaming", "Recording HQ"],
      current_profile: "Streaming",
      scene_collections: ["Podcast", "Gaming", "Interview"],
      current_scene_collection: "Gaming",
      stats: Obsctl::OBS::State::ObsStats.new(
        cpu_usage_percent: 3.2,
        memory_usage_mb: 742.0,
        available_disk_space_mb: 512_000.0,
        active_fps: 59.94,
        average_frame_render_time_ms: 1.42,
        render_skipped_frames: 12_i64,
        render_total_frames: 128_400_i64,
        output_skipped_frames: 340_i64,
        output_total_frames: 128_000_i64
      ),
      stream_bitrate_kbps: 5_842.0,
      stream_duration_ms: 4_215_000_i64,
      record_duration_ms: 4_215_000_i64
    )
    model.meter_levels["Mic/Aux"] = 0.62
    model.meter_levels["Desktop Audio"] = 0.24
    model.cpu_history = [2.1, 2.8, 3.6, 3.1, 2.9, 3.4, 4.0, 3.2, 2.7, 3.2]
    model.bitrate_history = [5_600.0, 5_720.0, 5_500.0, 5_842.0, 5_900.0, 5_780.0, 5_842.0]
    model.fps_history = [59.94, 59.94, 58.6, 59.94, 59.94, 59.9, 59.94, 59.94]
    model.anim.frame = 7_u64

    [
      {Obsctl::Runtime::LogLevel::Info, "connected to OBS 31.0.0", "obs_connected"},
      {Obsctl::Runtime::LogLevel::Info, "stream started -> 'Main Camera'", "obs_event"},
      {Obsctl::Runtime::LogLevel::Info, "profile switched -> Streaming", "obs_event"},
      {Obsctl::Runtime::LogLevel::Warn, "reconnect attempt 1 scheduled in 500ms", "obs_reconnect"},
      {Obsctl::Runtime::LogLevel::Info, "scene set: Main Camera", "command_ok"},
    ].each_with_index do |(level, message, code), index|
      model.push_log(Obsctl::TUI::LogEntry.new(level, message, code, Time.utc(2026, 8, 1, 21, 14, index * 7 + 2)))
    end

    model
  end

  # The MONO theme is built from ANSI indices rather than hex, so a palette
  # entry can resolve to nothing renderable; callers supply the fallback.
  def swatch(color : CryTUI::Color, fallback : String) : String
    css_color(color) || fallback
  end

  # Nil for `Reset`, which inherits whatever the page already has.
  def css_color(color : CryTUI::Color) : String?
    case color.kind
    when .rgb?     then "#%02x%02x%02x" % {color.red, color.green, color.blue}
    when .indexed? then INDEXED[color.index.to_i]? || "#c8c8c8"
    end
  end

  def escape(text : String) : String
    text.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;")
  end
end
