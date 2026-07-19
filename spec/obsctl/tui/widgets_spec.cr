require "../../spec_helper"
require "../../../src/obsctl/tui/widgets/header"
require "../../../src/obsctl/tui/widgets/scenes"
require "../../../src/obsctl/tui/widgets/audio"
require "../../../src/obsctl/tui/widgets/connection"
require "../../../src/obsctl/tui/widgets/live_bar"
require "../../../src/obsctl/tui/widgets/command_palette"
require "../../../src/obsctl/tui/widgets/dashboard"
require "../../../src/obsctl/tui/widgets/settings"
require "../../../src/obsctl/tui/widgets/splash"
require "../../../src/obsctl/tui/widgets/scene_map"

private def widget_model
  model = Obsctl::TUI::Model.new(theme: Obsctl::TUI::Theme::NORD)
  model.connected_to_daemon = true
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "30.1.0",
    obs_websocket_version: "5.0.0",
    current_scene: "Main",
    scenes: [
      Obsctl::OBS::State::SceneState.new("Main", alias: "m", shortcut: "1", active: true),
      Obsctl::OBS::State::SceneState.new("Cam", group: "Studio"),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new("Mic", alias: "mic", muted: false, volume_percent: 80),
      Obsctl::OBS::State::AudioState.new("Desktop", muted: true, volume_percent: 0),
    ],
    profiles: ["Default"],
    current_profile: "Default"
  )
  model.meter_levels["Mic"] = 0.1
  model
end

private def rendered_text(buffer : CryTUI::Buffer)
  buffer.lines.join("\n")
end

describe Obsctl::TUI::Widgets::LiveBar do
  it "renders active durations and OBS performance telemetry" do
    model = widget_model
    model.snapshot = model.snapshot.not_nil!.copy_with(
      output: Obsctl::OBS::State::OutputState.new(streaming: true, recording: true),
      stats: Obsctl::OBS::State::ObsStats.new(
        cpu_usage_percent: 12.5,
        memory_usage_mb: 768.0,
        active_fps: 59.9
      ),
      stream_bitrate_kbps: 4_500.0,
      stream_duration_ms: 65_000_i64,
      record_duration_ms: 3_661_000_i64
    )
    model.cpu_history = [5.0, 12.5]
    model.bitrate_history = [4_000.0, 4_500.0]
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 120, 4))

    Obsctl::TUI::Widgets::LiveBar.render(buffer.area, buffer, model)
    text = rendered_text(buffer)
    text.should contain("LIVE 01:05")
    text.should contain("REC 01:01:01")
    text.should contain("CPU 12.5%")
    text.should contain("FPS 59.9")
    text.should contain("MEM 768MB")
    text.should contain("NET 4500kbps")
  end

  it "keeps the waiting state before the first statistics sample" do
    model = widget_model
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 90, 4))
    Obsctl::TUI::Widgets::LiveBar.render(buffer.area, buffer, model)
    rendered_text(buffer).should contain("waiting for OBS metrics")
  end

  it "uses compact telemetry when only one inner row is available" do
    model = widget_model
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 100, 3))

    Obsctl::TUI::Widgets::LiveBar.render(buffer.area, buffer, model)

    rendered_text(buffer).should contain("telemetry waiting…")
  end
end

describe Obsctl::TUI::Widgets::Logs do
  it "semantically highlights resources, commands, statuses, and numbers" do
    model = widget_model
    model.snapshot = model.snapshot.not_nil!.copy_with(profiles: ["Streaming"], scene_collections: ["Podcast"])
    message = "scene Main switched -> profile Streaming via /scene in 42ms; OBS connected"
    spans = Obsctl::TUI::Widgets::Logs.highlight_message(message, model)
    spans.map(&.content).join.should eq(message)

    spans.find(&.content.==("Main")).not_nil!.style.foreground.should eq(model.theme.accent)
    spans.find(&.content.==("Streaming")).not_nil!.style.foreground.should eq(model.theme.warning)
    spans.find(&.content.==("switched")).not_nil!.style.foreground.should eq(model.theme.success)
    spans.find(&.content.==("/scene")).not_nil!.style.foreground.should eq(model.theme.accent)
    spans.find(&.content.==("42ms")).not_nil!.style.foreground.should eq(model.theme.info)
    spans.find(&.content.==("OBS")).not_nil!.style.foreground.should eq(model.theme.accent_alt)
  end

  it "highlights quoted resources and respects resource word boundaries" do
    model = widget_model
    spans = Obsctl::TUI::Widgets::Logs.highlight_message(
      "failed on 'Main'; Mainframe timeout on Desktop",
      model
    )

    spans.find(&.content.==("failed")).not_nil!.style.foreground.should eq(model.theme.danger)
    spans.find(&.content.==("'Main'")).not_nil!.style.foreground.should eq(model.theme.accent)
    spans.find(&.content.==("Mainframe")).not_nil!.style.foreground.should eq(model.theme.foreground)
    spans.find(&.content.==("timeout")).not_nil!.style.foreground.should eq(model.theme.danger)
    spans.find(&.content.==("Desktop")).not_nil!.style.foreground.should eq(model.theme.info)
  end
end

describe Obsctl::TUI::Widgets::Header do
  it "renders daemon, OBS, scene, profile, and frame status" do
    model = widget_model
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 110, 4))
    Obsctl::TUI::Widgets::Header.render(buffer.area, buffer, model)
    text = rendered_text(buffer)

    text.should contain("OBSCTL // BROADCAST COMMAND CENTER")
    text.should contain("obsctl")
    text.should contain("daemon: connected")
    text.should contain("OBS: connected (v30.1.0)")
    text.should contain("scene: Main")
    text.should contain("profile: Default")
  end

  it "renders the animated gradient as styled block-title cells" do
    model = widget_model
    model.anim.frame = 7_u64
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 110, 4))
    Obsctl::TUI::Widgets::Header.render(buffer.area, buffer, model)

    title_colors = (3...38).compact_map { |x| buffer[x, 0].style.foreground }.uniq
    title_colors.size.should be > 2
  end

  it "uses the rich bullet and simplified ASCII header separators" do
    model = widget_model
    rich = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 80, 4))
    Obsctl::TUI::Widgets::Header.render(rich.area, rich, model)
    rendered_text(rich).should contain("console  •  frame")

    model.advanced_ui = false
    simple = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 80, 4))
    Obsctl::TUI::Widgets::Header.render(simple.area, simple, model)
    rendered_text(simple).should contain("console  |  frame")
  end

  it "renders disconnected state without a snapshot" do
    model = Obsctl::TUI::Model.new(advanced_ui: false)
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 70, 4))
    Obsctl::TUI::Widgets::Header.render(buffer.area, buffer, model)
    rendered_text(buffer).should contain("daemon: disconnected")
  end
end

describe Obsctl::TUI::Widgets::Scenes do
  it "renders scene metadata and highlights the selected row" do
    model = widget_model
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 64, 7))
    Obsctl::TUI::Widgets::Scenes.render(buffer.area, buffer, model)
    text = rendered_text(buffer)

    text.should contain("Scenes")
    text.should contain("Main (m) [1]")
    text.should contain("Cam")
    text.should contain("Studio")
    buffer[10, 1].style.background.should eq(model.theme.highlight_background)
  end

  it "decays a switched-scene flash across eight animation ticks" do
    model = widget_model
    model.scene_flash = {"Main", 10_u64}

    colors = [10_u64, 14_u64, 18_u64].map do |frame|
      model.anim.frame = frame
      buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 64, 7))
      Obsctl::TUI::Widgets::Scenes.render(buffer.area, buffer, model)
      buffer[8, 1].style.foreground
    end

    colors[0].should eq(model.theme.accent)
    colors[1].should eq(Obsctl::TUI::Anim.blend(model.theme.success, model.theme.accent, 0.5))
    colors[2].should eq(model.theme.foreground)
  end

  it "renders an empty panel without selecting a row" do
    model = Obsctl::TUI::Model.new
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 40, 4))
    Obsctl::TUI::Widgets::Scenes.render(buffer.area, buffer, model)
    rendered_text(buffer).should contain("Scenes")
  end
end

describe Obsctl::TUI::Widgets::Audio do
  it "renders mute state, volume, alias, and logarithmic meter" do
    model = widget_model
    model.focus = Obsctl::TUI::FocusPanel::Audio
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 76, 8))
    Obsctl::TUI::Widgets::Audio.render(buffer.area, buffer, model)
    text = rendered_text(buffer)

    text.should contain("Audio Matrix")
    text.should contain("Mic (mic) 80%")
    text.should contain("Desktop 0%")
    text.should contain("dB")
    text.should contain("▰")
    buffer[12, 1].style.background.should eq(model.theme.highlight_background)
    buffer[12, 2].style.background.should eq(model.theme.highlight_background)
  end

  it "renders unknown mute state without claiming the input is active" do
    model = widget_model
    model.snapshot = model.snapshot.not_nil!.copy_with(audio_inputs: [
      Obsctl::OBS::State::AudioState.new("Pending", muted: nil),
    ])
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 50, 5))
    Obsctl::TUI::Widgets::Audio.render(buffer.area, buffer, model)

    text = rendered_text(buffer)
    text.should contain("Pending")
    text.should_not contain("🔊")
  end
end

describe Obsctl::TUI::Theme do
  it "resolves built-in themes and parses custom hex colors safely" do
    Obsctl::TUI::Theme.by_id("Nord").should eq(Obsctl::TUI::Theme::NORD)
    Obsctl::TUI::Theme.by_id("unknown").should eq(Obsctl::TUI::Theme::CLAUDE)
    Obsctl::TUI::Theme.parse_hex("#12abEF").should eq(CryTUI::Color.rgb(0x12, 0xAB, 0xEF))
    Obsctl::TUI::Theme.parse_hex("nope").should be_nil
  end
end

describe Obsctl::TUI::Widgets::Connection do
  it "renders actionable server-unavailable guidance" do
    model = Obsctl::TUI::Model.new
    model.last_result = "connection refused"
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 72, 14))
    Obsctl::TUI::Widgets::Connection.render_unavailable(buffer.area, buffer, model)
    text = rendered_text(buffer)
    text.should contain("obsctl — daemon unavailable")
    text.should contain("connection refused")
    text.should contain("obsctl server --headless")
    text.should contain("systemctl --user enable --now obsctl.service")
  end
end

describe Obsctl::TUI::Widgets::CommandPalette do
  it "renders active input, cursor, result reveal, and completions" do
    model = widget_model
    model.command_palette.active = true
    model.command_palette.input = "/scene M"
    model.command_palette.completions = ["/scene Main", "/scene Media"]
    model.command_palette.completion_index = 1
    model.set_last_result("scene changed")
    model.anim.tick
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 100, 5))
    Obsctl::TUI::Widgets::CommandPalette.render(buffer.area, buffer, model)
    text = rendered_text(buffer)
    text.should contain("Command Palette")
    text.should contain("/scene M")
    text.should contain("[/scene Main]")
    text.should contain("[/scene Media]")
    text.should contain("sce")
  end
end

describe Obsctl::TUI::DashboardLayout do
  it "overlaps adjacent panel edges at 100x40" do
    areas = Obsctl::TUI::DashboardLayout.compute(CryTUI::Rect.new(0, 0, 100, 40))
    areas.header.height.should eq(4)
    areas.live_bar.height.should eq(5)
    areas.scenes.height.should be > areas.profiles.height
    areas.scenes.width.should eq(50)
    areas.audio.x.should eq(49)
    areas.scenes.right.should eq(areas.audio.x + 1)
    areas.audio.right.should eq(100)
    areas.header.bottom.should eq(areas.live_bar.y + 1)
    areas.palette.bottom.should eq(40)
    areas.profiles.height.should eq(8)
    areas.logs.height.should eq(8)
    areas.palette.height.should eq(5)
  end
end

describe Obsctl::TUI::Widgets::Dashboard do
  it "renders the complete primary dashboard into one frame" do
    model = widget_model
    model.snapshot = model.snapshot.not_nil!.copy_with(scene_collections: ["Podcast", "Gaming"], current_scene_collection: "Podcast")
    model.logs << Obsctl::TUI::LogEntry.new(Obsctl::Runtime::LogLevel::Warn, "reconnect attempt", "obs_reconnect", Time.utc(2026, 7, 18, 12, 34, 56))
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 120, 40))
    Obsctl::TUI::Widgets::Dashboard.render(buffer.area, buffer, model)
    text = rendered_text(buffer)

    ["BROADCAST COMMAND CENTER", "LIVE TELEMETRY", "Scenes", "Audio Matrix", "Profiles", "Collections", "Logs // Event Stream", "Command Palette"].each do |label|
      text.should contain(label)
    end
    text.should contain("reconnect attempt")
    buffer[119, 39].style.background.should eq(model.theme.background)

    areas = Obsctl::TUI::DashboardLayout.compute(buffer.area)
    buffer[areas.audio.x, areas.audio.y].symbol.should eq("┬")
    buffer[areas.audio.x, areas.scenes.bottom - 1].symbol.should eq("┼")
    buffer[areas.header.x, areas.live_bar.y].symbol.should eq("├")
    buffer[areas.header.right - 1, areas.live_bar.y].symbol.should eq("┤")
    buffer[areas.audio.right - 1, areas.audio.y].symbol.should eq("┤")
    buffer[areas.logs.right - 1, areas.logs.y].symbol.should eq("┤")
    buffer[areas.palette.right - 1, areas.palette.y].symbol.should eq("┤")
    buffer[areas.palette.right - 1, areas.palette.bottom - 1].symbol.should eq("╯")
  end
end

describe Obsctl::TUI::Widgets::Settings do
  it "renders a scrollable palette list and semantic live preview" do
    model = widget_model
    model.settings_cursor = Obsctl::TUI::Theme::ALL.size - 1
    model.theme = Obsctl::TUI::Theme::MONO
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 100, 18))
    Obsctl::TUI::Widgets::Settings.render(buffer.area, buffer, model)
    text = rendered_text(buffer)

    text.should contain("Themes // 29 palettes")
    text.should contain("Mono (TTY-safe)")
    text.should contain("Preview: Mono (TTY-safe)")
    text.should contain("SCENE ACTIVE")
  end
end

describe Obsctl::TUI::Widgets::Splash do
  it "renders responsive rich, compact, and ASCII startup identities" do
    model = widget_model
    large = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 100, 20))
    Obsctl::TUI::Widgets::Splash.render(large.area, large, model, 20_u64, 40_u64)
    rendered_text(large).should contain("STUDIO LINK")
    rendered_text(large).should contain("Broadcast control, without breaking flow.")

    compact = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 60, 12))
    Obsctl::TUI::Widgets::Splash.render(compact.area, compact, model, 20_u64, 40_u64)
    rendered_text(compact).should contain("INITIALIZING BROADCAST CONTROL")

    ascii_model = Obsctl::TUI::Model.new(advanced_ui: false, show_icons: false)
    ascii = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 70, 15))
    Obsctl::TUI::Widgets::Splash.render(ascii.area, ascii, ascii_model, 20_u64, 40_u64)
    rendered_text(ascii).should contain("OBSCTL STARTUP")
    rendered_text(ascii).should contain("50%")
  end

  it "renders the same staged boot vocabulary as the Rust splash" do
    model = widget_model
    expected = {
       0_u64 => "loading control surfaces",
      10_u64 => "warming animation engine",
      20_u64 => "syncing OBS telemetry",
      30_u64 => "painting command center",
      40_u64 => "ready",
    }
    expected.each do |frame, message|
      buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 60, 12))
      Obsctl::TUI::Widgets::Splash.render(buffer.area, buffer, model, frame, 40_u64)
      rendered_text(buffer).should contain(message)
    end
  end

  it "alternates the LIVE identity badge between filled and outline phases" do
    model = widget_model
    filled = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 60, 12))
    outline = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 60, 12))
    Obsctl::TUI::Widgets::Splash.render(filled.area, filled, model, 0_u64, 40_u64)
    Obsctl::TUI::Widgets::Splash.render(outline.area, outline, model, 2_u64, 40_u64)

    filled_live = filled.cells.find { |cell| cell.symbol == "L" && cell.style.background }
    outline_live = outline.cells.find { |cell| cell.symbol == "L" && cell.style.modifiers.bold? && cell.style.background == model.theme.background }
    filled_live.should_not be_nil
    outline_live.should_not be_nil
  end
end

describe Obsctl::TUI::Widgets::SceneMap do
  it "sorts groups, separates ungrouped scenes, and marks the active scene" do
    model = widget_model
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 50, 12))
    Obsctl::TUI::Widgets::SceneMap.render(buffer.area, buffer, model)
    text = rendered_text(buffer)
    text.should contain("Scene Map")
    text.should contain("[Studio]")
    text.should contain("[ungrouped]")
    text.should contain("▶ Main")
    text.index("[Studio]").not_nil!.should be < text.index("[ungrouped]").not_nil!
  end
end
