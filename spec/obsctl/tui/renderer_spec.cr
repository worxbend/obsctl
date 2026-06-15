require "../../spec_helper"
require "../../../src/obsctl/tui/renderer"

private def renderer_snapshot
  Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: "Main Camera",
    scenes: [
      Obsctl::OBS::State::SceneState.new(name: "Main Camera", alias: "main", shortcut: "1", group: "Live", active: true),
      Obsctl::OBS::State::SceneState.new(name: "BRB", alias: "brb", shortcut: "2", group: "Breaks", active: false),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new(name: "Mic/Aux", alias: "mic", shortcut: "m", muted: false, volume_percent: 70),
    ]
  )
end

describe Obsctl::TUI::Renderer do
  it "renders dashboard panels from the TUI model" do
    model = Obsctl::TUI::Model.new(
      snapshot: renderer_snapshot,
      command_line: "/scene main",
      last_result: "ready",
      logs: ["warn command_failed: OBS is unavailable"]
    )
    io = IO::Memory.new

    Obsctl::TUI::Renderer.new.render(model, io)
    output = io.to_s

    output.should contain("obsctl-cr | OBS connected | scene Main Camera")
    output.should contain("Scenes")
    output.should contain("> Main Camera [alias=main key=1 group=Live]")
    output.should contain("Scene Map")
    output.should contain("Live")
    output.should contain("Audio")
    output.should contain("Mic/Aux live vol=70% [alias=mic key=m]")
    output.should contain("Recent Logs")
    output.should contain("warn command_failed: OBS is unavailable")
    output.should contain("> /scene main")
  end

  it "bounds rendered output to the requested viewport" do
    scenes = (1..20).map do |index|
      Obsctl::OBS::State::SceneState.new(
        name: "Very Long Scene Name #{index} With Extra Words",
        alias: "scene-#{index}",
        shortcut: index.to_s,
        group: "Group #{index % 3}",
        active: index == 1
      )
    end
    audio_inputs = (1..12).map do |index|
      Obsctl::OBS::State::AudioState.new(
        name: "Very Long Audio Input #{index} With Extra Words",
        alias: "audio-#{index}",
        shortcut: "a#{index}",
        muted: index.even?,
        volume_percent: 50
      )
    end
    snapshot = Obsctl::OBS::State::ObsSnapshot.new(
      connected: true,
      obs_studio_version: "31.0.0",
      obs_websocket_version: "5.5.0",
      current_scene: "Very Long Scene Name 1 With Extra Words",
      scenes: scenes,
      audio_inputs: audio_inputs
    )
    model = Obsctl::TUI::Model.new(
      snapshot: snapshot,
      command_line: "/scene \"Very Long Scene Name 1 With Extra Words\"",
      last_result: "ready",
      logs: (1..10).map { |index| "warn long log entry #{index} with extra detail" }
    )
    io = IO::Memory.new

    Obsctl::TUI::Renderer.new.render(model, io, width: 50, height: 14)
    output = io.to_s.sub("\e[2J\e[H", "")
    lines = output.lines(chomp: true)

    lines.size.should be <= 14
    lines.each do |line|
      line.size.should be <= 50
    end
    output.should contain("~")
  end
end
