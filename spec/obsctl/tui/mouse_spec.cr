require "../../spec_helper"
require "../../../src/obsctl/tui/input"

private AREA = CryTUI::Rect.new(0, 0, 120, 40)

private def mouse_model
  model = Obsctl::TUI::Model.new
  model.connected_to_daemon = true
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: "Main Camera",
    scenes: [
      Obsctl::OBS::State::SceneState.new("Main Camera", active: true),
      Obsctl::OBS::State::SceneState.new("Screen Share"),
      Obsctl::OBS::State::SceneState.new("Guest Cam"),
    ],
    audio_inputs: [
      Obsctl::OBS::State::AudioState.new("Mic/Aux", muted: false, volume_percent: 72),
      Obsctl::OBS::State::AudioState.new("Desktop Audio", muted: true, volume_percent: 40),
    ],
    profiles: ["Default", "Streaming"],
    current_profile: "Default",
    scene_collections: ["Podcast", "Gaming"],
    current_scene_collection: "Podcast"
  )
  model
end

private def click(model, column, row, button = CryTUI::MouseButton::Left)
  Obsctl::TUI::Input.handle_mouse(
    model,
    CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, button, column, row),
    AREA
  )
end

private def wheel(model, column, row, up : Bool, modifiers = CryTUI::KeyModifiers::None)
  Obsctl::TUI::Input.handle_mouse(
    model,
    CryTUI::MouseEvent.new(
      up ? CryTUI::MouseKind::ScrollUp : CryTUI::MouseKind::ScrollDown,
      CryTUI::MouseButton::None, column, row, modifiers
    ),
    AREA
  )
end

# The first row inside a panel's border, where its first item is drawn.
private def first_item_row(area : CryTUI::Rect)
  area.y + 1
end

describe Obsctl::TUI::HitTest do
  it "resolves a point to the panel and row drawn there" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)

    scenes = Obsctl::TUI::HitTest.resolve(model, AREA, areas.scenes.x + 4, first_item_row(areas.scenes) + 2).not_nil!
    scenes.panel.should eq(Obsctl::TUI::FocusPanel::Scenes)
    scenes.index.should eq(2)

    profiles = Obsctl::TUI::HitTest.resolve(model, AREA, areas.profiles.x + 4, first_item_row(areas.profiles) + 1).not_nil!
    profiles.panel.should eq(Obsctl::TUI::FocusPanel::Profiles)
    profiles.index.should eq(1)

    collections = Obsctl::TUI::HitTest.resolve(model, AREA, areas.collections.x + 4, first_item_row(areas.collections)).not_nil!
    collections.panel.should eq(Obsctl::TUI::FocusPanel::Collections)
    collections.index.should eq(0)
  end

  it "identifies the panel but no row when the pointer is past the last item" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)

    target = Obsctl::TUI::HitTest.resolve(model, AREA, areas.scenes.x + 4, areas.scenes.bottom - 2).not_nil!
    target.panel.should eq(Obsctl::TUI::FocusPanel::Scenes)
    target.index.should be_nil
  end

  it "counts an audio input as two rows once it has a meter" do
    model = mouse_model
    # Only the first input has a level, so only it grows a meter row.
    model.meter_levels["Mic/Aux"] = 0.5
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)
    top = first_item_row(areas.audio)

    Obsctl::TUI::HitTest.resolve(model, AREA, areas.audio.x + 8, top).not_nil!.index.should eq(0)
    Obsctl::TUI::HitTest.resolve(model, AREA, areas.audio.x + 8, top + 1).not_nil!.index.should eq(0)
    Obsctl::TUI::HitTest.resolve(model, AREA, areas.audio.x + 8, top + 2).not_nil!.index.should eq(1)
  end

  it "marks the mute glyph at the start of an audio row" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)
    top = first_item_row(areas.audio)

    Obsctl::TUI::HitTest.resolve(model, AREA, areas.audio.x + 1, top).not_nil!.on_mute_control.should be_true
    Obsctl::TUI::HitTest.resolve(model, AREA, areas.audio.x + 8, top).not_nil!.on_mute_control.should be_false
  end

  it "follows the list as it scrolls, so a click lands on what is drawn" do
    model = mouse_model
    scenes = (1..40).map { |index| Obsctl::OBS::State::SceneState.new("Scene #{index}") }
    model.snapshot = model.snapshot.not_nil!.copy_with(scenes: scenes)
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)
    rows = areas.scenes.height - 2

    # Selecting the last scene scrolls the panel; the top row is no longer
    # scene 0, and hit testing has to agree with the renderer about that.
    model.scene_cursor = scenes.size - 1
    top = Obsctl::TUI::HitTest.resolve(model, AREA, areas.scenes.x + 4, first_item_row(areas.scenes)).not_nil!
    top.index.should eq(scenes.size - rows)

    bottom = Obsctl::TUI::HitTest.resolve(model, AREA, areas.scenes.x + 4, first_item_row(areas.scenes) + rows - 1).not_nil!
    bottom.index.should eq(scenes.size - 1)
  end

  it "ignores the pointer while the palette or settings own the screen" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)
    column, row = areas.scenes.x + 4, first_item_row(areas.scenes)

    model.command_palette.active = true
    Obsctl::TUI::HitTest.resolve(model, AREA, column, row).should be_nil

    model.command_palette.active = false
    model.view = Obsctl::TUI::View::Settings
    Obsctl::TUI::HitTest.resolve(model, AREA, column, row).should be_nil
  end
end

describe "mouse input" do
  it "focuses and selects on the first click, and activates on the second" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)
    row = first_item_row(areas.scenes) + 2

    first = click(model, areas.scenes.x + 4, row).not_nil!
    first.kind.should eq(Obsctl::TUI::ActionKind::PointerFocus)
    first.panel.should eq(Obsctl::TUI::FocusPanel::Scenes)
    first.index.should eq(2)

    # Standing in for the dispatcher having applied that focus.
    model.focus = Obsctl::TUI::FocusPanel::Scenes
    model.scene_cursor = 2

    second = click(model, areas.scenes.x + 4, row).not_nil!
    second.kind.should eq(Obsctl::TUI::ActionKind::PointerActivate)
    second.index.should eq(2)
  end

  it "never activates a scene the pointer has not already selected" do
    model = mouse_model
    model.focus = Obsctl::TUI::FocusPanel::Scenes
    model.scene_cursor = 0
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)

    # A stray click on another row must not cut the programme scene.
    action = click(model, areas.scenes.x + 4, first_item_row(areas.scenes) + 1).not_nil!
    action.kind.should eq(Obsctl::TUI::ActionKind::PointerFocus)
  end

  it "toggles mute from the glyph without needing the row selected first" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)

    action = click(model, areas.audio.x + 1, first_item_row(areas.audio) + 1).not_nil!
    action.kind.should eq(Obsctl::TUI::ActionKind::PointerToggleMute)
    action.panel.should eq(Obsctl::TUI::FocusPanel::Audio)
    action.index.should eq(1)
  end

  it "scrolls the panel under the pointer, focusing it first when it is not" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)
    column, row = areas.profiles.x + 4, first_item_row(areas.profiles)

    # Focus is on scenes, so the wheel moves focus rather than the wrong cursor.
    wheel(model, column, row, false).not_nil!.kind.should eq(Obsctl::TUI::ActionKind::PointerFocus)

    model.focus = Obsctl::TUI::FocusPanel::Profiles
    wheel(model, column, row, false).not_nil!.kind.should eq(Obsctl::TUI::ActionKind::NavigateDown)
    wheel(model, column, row, true).not_nil!.kind.should eq(Obsctl::TUI::ActionKind::NavigateUp)
  end

  it "treats the wheel as a gain control over the audio matrix" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)
    second_row = first_item_row(areas.audio) + 1

    # No selection needed first: the wheel acts on the input it is over.
    up = wheel(model, areas.audio.x + 8, second_row, true).not_nil!
    up.kind.should eq(Obsctl::TUI::ActionKind::PointerVolumeUp)
    up.index.should eq(1)

    down = wheel(model, areas.audio.x + 8, second_row, false).not_nil!
    down.kind.should eq(Obsctl::TUI::ActionKind::PointerVolumeDown)
    down.index.should eq(1)
  end

  it "still moves through the audio list when shift is held" do
    model = mouse_model
    model.focus = Obsctl::TUI::FocusPanel::Audio
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)

    action = wheel(model, areas.audio.x + 8, first_item_row(areas.audio), false, CryTUI::KeyModifiers::Shift).not_nil!
    action.kind.should eq(Obsctl::TUI::ActionKind::NavigateDown)
  end

  it "does not change gain when the wheel is over empty audio space" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)

    action = wheel(model, areas.audio.x + 8, areas.audio.bottom - 2, true).not_nil!
    action.kind.should eq(Obsctl::TUI::ActionKind::PointerFocus)
  end

  it "does nothing for buttons and releases the dashboard does not bind" do
    model = mouse_model
    areas = Obsctl::TUI::DashboardLayout.compute(AREA, false)
    column, row = areas.scenes.x + 4, first_item_row(areas.scenes)

    click(model, column, row, CryTUI::MouseButton::Right).should be_nil
    Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Release, CryTUI::MouseButton::Left, column, row),
      AREA
    ).should be_nil
    # A click on the chrome between panels is not an error, just not an action.
    click(model, AREA.right - 1, AREA.bottom - 1).should be_nil
  end
end

describe "which-key mouse" do
  it "runs the binding under the pointer and closes on a click outside" do
    model = mouse_model
    model.pending_sequence = "<leader>"
    entries = Obsctl::TUI::Keymap.continuations("<leader>")
    rect = Obsctl::TUI::HitTest.which_key_area(model, AREA)
    row = entries.index! { |entry| entry.token == "q" }

    quit = click(model, rect.x + 2, rect.y + 1 + row).not_nil!
    quit.kind.should eq(Obsctl::TUI::ActionKind::Quit)

    group = entries.index! { |entry| entry.token == "f" }
    opened = click(model, rect.x + 2, rect.y + 1 + group).not_nil!
    opened.kind.should eq(Obsctl::TUI::ActionKind::PendingSequence)
    opened.sequence.should eq("<leader>f")

    click(model, 0, 0).not_nil!.kind.should eq(Obsctl::TUI::ActionKind::ClearSequence)
  end
end

describe "appearance lab mouse" do
  it "previews the theme under the pointer and applies the previewed one" do
    model = mouse_model
    model.view = Obsctl::TUI::View::Settings
    themes = Obsctl::TUI::SettingsLayout.compute(AREA).themes

    preview = click(model, themes.x + 4, first_item_row(themes) + 2).not_nil!
    preview.kind.should eq(Obsctl::TUI::ActionKind::PointerSettingsSelect)
    preview.index.should eq(2)

    model.settings_cursor = 2
    click(model, themes.x + 4, first_item_row(themes) + 2).not_nil!.kind
      .should eq(Obsctl::TUI::ActionKind::PointerSettingsApply)

    wheel(model, themes.x + 4, first_item_row(themes), false).not_nil!.kind
      .should eq(Obsctl::TUI::ActionKind::SettingsNavigateDown)
  end
end

describe "palette mouse" do
  it "picks the completion chip under the pointer" do
    model = mouse_model
    model.command_palette.active = true
    model.command_palette.completions = ["/scene", "/screenshot"]
    palette = Obsctl::TUI::HitTest.palette_area(model, AREA)
    chips = Obsctl::TUI::PaletteLayout.chips(model.command_palette.completions, palette)
    row = Obsctl::TUI::PaletteLayout.completion_row(palette)

    picked = click(model, chips[1][0], row).not_nil!
    picked.kind.should eq(Obsctl::TUI::ActionKind::PointerCompletion)
    picked.index.should eq(1)

    # The chips end well before the panel does, so this lands on the panel but
    # on no chip -- a miss, not a pick.
    click(model, chips[1][1] + 2, row).should be_nil
    wheel(model, chips[0][0], row, true).not_nil!.kind.should eq(Obsctl::TUI::ActionKind::CompletePrevious)
  end

  it "closes the palette when the click lands outside it" do
    model = mouse_model
    model.command_palette.active = true
    click(model, 0, 0).not_nil!.kind.should eq(Obsctl::TUI::ActionKind::ClosePalette)
  end
end
