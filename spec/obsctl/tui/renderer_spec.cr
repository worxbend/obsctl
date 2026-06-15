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
end
