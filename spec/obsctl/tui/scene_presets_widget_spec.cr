require "../../spec_helper"
require "../../../src/obsctl/tui/input"
require "../../../src/obsctl/tui/widgets/scene_presets"

private AREA = CryTUI::Rect.new(0, 0, 120, 40)

# "Utility Cam" is flagged hidden by the daemon and "BRB Loop" is hidden only
# by the draft, so one spec model covers both ways a scene can be out of the
# dashboard's scene list -- and the editor has to list them either way.
private def preset_widget_model(names = ["Main", "Utility Cam", "BRB Loop"], hidden_in_obs = ["Utility Cam"])
  model = Obsctl::TUI::Model.new(theme: Obsctl::TUI::Theme::NORD)
  model.connected_to_daemon = true
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: names.first?,
    scenes: names.map_with_index do |name, index|
      Obsctl::OBS::State::SceneState.new(name, active: index == 0, hidden: hidden_in_obs.includes?(name))
    end,
    audio_inputs: [] of Obsctl::OBS::State::AudioState
  )
  model
end

private def open_preset_editor(model, hidden = ["BRB Loop"], name = "")
  model.scene_preset_editor = Obsctl::TUI::ScenePresetEditorState.new(
    active: true,
    name: name,
    hidden: hidden.to_set
  )
  model
end

private def render_presets(model, width = 120, height = 40)
  buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, width, height))
  Obsctl::TUI::Widgets::ScenePresets.render(buffer.area, buffer, model)
  buffer
end

private def preset_rendered_text(buffer : CryTUI::Buffer)
  buffer.lines.join("\n")
end

# The style the widget drew a scene's name with, found by the first cell of
# that name that carries a foreground of its own.
private def preset_name_cell(buffer : CryTUI::Buffer, initial : Char)
  buffer.cells.find { |cell| cell.symbol == initial.to_s && cell.style.foreground }
end

describe Obsctl::TUI::Widgets::ScenePresets do
  it "draws nothing at all while the editor is closed" do
    preset_rendered_text(render_presets(preset_widget_model())).strip.should be_empty
  end

  it "lists every scene, including ones hidden by OBS and ones hidden by the draft" do
    text = preset_rendered_text(render_presets(open_preset_editor(preset_widget_model())))
    text.should contain("Scene presets")
    text.should contain("Main")
    text.should contain("Utility Cam")
    text.should contain("BRB Loop")
  end

  it "dims a hidden scene's name and leaves a visible one undimmed" do
    buffer = render_presets(open_preset_editor(preset_widget_model()))
    hidden = preset_name_cell(buffer, 'B').should_not be_nil
    visible = preset_name_cell(buffer, 'M').should_not be_nil

    hidden.style.modifiers.dim?.should be_true
    hidden.style.foreground.should eq(Obsctl::TUI::Theme::NORD.muted)
    visible.style.modifiers.dim?.should be_false
    visible.style.foreground.should_not eq(Obsctl::TUI::Theme::NORD.muted)
  end

  it "marks hidden and visible scenes differently without changing the row width" do
    model = open_preset_editor(preset_widget_model())
    scenes = model.all_scenes
    hidden = scenes.find! { |scene| scene.name == "BRB Loop" }
    visible = scenes.find! { |scene| scene.name == "Main" }

    hidden_row = Obsctl::TUI::ScenePresetsLayout.row_text(model, hidden)
    visible_row = Obsctl::TUI::ScenePresetsLayout.row_text(model, visible)
    Obsctl::TUI::ScenePresetsLayout.marker(model, true).should_not eq(Obsctl::TUI::ScenePresetsLayout.marker(model, false))
    # Same scene name length either side, so any difference in width would be
    # the marker's -- and a marker that changed width would move the box the
    # hit test measures against.
    CryTUI::TextWidth.width(hidden_row.sub("BRB Loop", "Main")).should eq(CryTUI::TextWidth.width(visible_row))
  end

  it "titles the box with the draft's name, or `unnamed` before one is given" do
    preset_rendered_text(render_presets(open_preset_editor(preset_widget_model()))).should contain("unnamed")
    preset_rendered_text(render_presets(open_preset_editor(preset_widget_model(), name: "streaming"))).should contain("streaming")
  end

  it "shows the typed name and the confirm hints while a name is being entered" do
    model = open_preset_editor(preset_widget_model())
    model.scene_preset_editor.naming = true
    model.scene_preset_editor.name_input = "editing"
    text = preset_rendered_text(render_presets(model))

    text.should contain("editing")
    text.should contain("confirm")
    text.should contain("cancel")
    # The list-mode hints are gone: the two sets never share the title, or the
    # box would be measured around one and drawn with the other.
    text.should_not contain("t hide")
  end

  it "keeps every key on a row of its own, cycling included" do
    text = preset_rendered_text(render_presets(open_preset_editor(preset_widget_model())))

    text.should contain("t hide")
    text.should contain("n name")
    # The keys that load another saved preset are the point of saving more than
    # one, so they cannot be left to the README.
    text.should contain("switch preset")
    text.should contain("esc close")
  end

  it "keeps the way out on screen whatever the preset is called" do
    long = "streaming-and-recording-and-everything-else"
    model = open_preset_editor(preset_widget_model(), name: long)

    # A name is user text of any length. It gets what the heading leaves of the
    # box and no more, so it can never push the keys off the row they are on.
    {AREA, CryTUI::Rect.new(0, 0, 80, 24), CryTUI::Rect.new(0, 0, 40, 12)}.each do |area|
      rect = Obsctl::TUI::ScenePresetsLayout.compute(area, model)
      title = CryTUI::TextWidth.width(Obsctl::TUI::ScenePresetsLayout.title_parts(model, rect.width).join)

      rect.width.should be <= Obsctl::TUI::ScenePresetsLayout::MAX_WIDTH
      title.should be <= rect.width - 2
      text = preset_rendered_text(render_presets(model, width: area.width, height: area.height))
      text.should contain("close")
      text.should contain("Scene presets")
    end
  end

  it "keeps the caret on screen however much has been typed" do
    model = open_preset_editor(preset_widget_model())
    model.scene_preset_editor.naming = true

    {"short", "a" * 40, "b" * 200}.each do |typed|
      model.scene_preset_editor.name_input = typed
      rect = Obsctl::TUI::ScenePresetsLayout.compute(AREA, model)
      title = Obsctl::TUI::ScenePresetsLayout.title_parts(model, rect.width).join

      CryTUI::TextWidth.width(title).should be <= rect.width - 2
      # The end of the field, not the beginning: without the caret on screen a
      # long name is typed blind, with nothing on the display changing.
      title.should contain("█")
      title.should contain(typed[-4..])
      preset_rendered_text(render_presets(model)).should contain("cancel")
    end
  end

  it "stays off a terminal too small to be worth taking over" do
    model = open_preset_editor(preset_widget_model())
    Obsctl::TUI::ScenePresetsLayout.compute(CryTUI::Rect.new(0, 0, 20, 6), model).empty?.should be_true
    preset_rendered_text(render_presets(model, width: 20, height: 6)).strip.should be_empty
  end

  it "stays off when there are no scenes to list" do
    model = open_preset_editor(preset_widget_model([] of String, [] of String))
    Obsctl::TUI::ScenePresetsLayout.compute(AREA, model).empty?.should be_true
    preset_rendered_text(render_presets(model)).strip.should be_empty
  end
end

describe "scene preset editor mouse" do
  it "toggles the scene under the pointer and closes on a click outside" do
    model = open_preset_editor(preset_widget_model())
    rect = Obsctl::TUI::ScenePresetsLayout.compute(AREA, model)

    inside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, rect.x + 2, rect.y + 2),
      AREA
    )
    inside.try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsToggleScene)
    inside.try(&.index).should eq(1)

    outside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 0, 0),
      AREA
    )
    outside.try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseScenePresets)
  end

  it "treats the hint row as chrome rather than as the scene it lines up with" do
    model = open_preset_editor(preset_widget_model())
    rect = Obsctl::TUI::ScenePresetsLayout.compute(AREA, model)

    # The row is inside the border, so without the list's own box the hit test
    # would resolve it to whichever scene the list scrolled under it.
    Obsctl::TUI::HitTest.scene_presets_index(
      model, AREA, rect.x + 2, Obsctl::TUI::ScenePresetsLayout.hint_row(rect)
    ).should be_nil
  end

  it "walks the list with the wheel" do
    model = open_preset_editor(preset_widget_model())
    rect = Obsctl::TUI::ScenePresetsLayout.compute(AREA, model)

    up = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::ScrollUp, CryTUI::MouseButton::None, rect.x + 2, rect.y + 1),
      AREA
    )
    down = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::ScrollDown, CryTUI::MouseButton::None, rect.x + 2, rect.y + 1),
      AREA
    )
    up.try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNavigateUp)
    down.try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNavigateDown)
  end
end
