require "../../spec_helper"
require "../../../src/obsctl/tui/input"

private AREA = CryTUI::Rect.new(0, 0, 120, 40)

# Three scenes, one of which OBS reports as hidden. The editor is the only
# surface that lists that third row, so every example here needs it present.
private def preset_model(names = ["Main", "Utility", "Cam"], hidden = ["Utility"])
  model = Obsctl::TUI::Model.new
  model.connected_to_daemon = true
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: names.first?,
    scenes: names.map_with_index do |name, index|
      Obsctl::OBS::State::SceneState.new(name, active: index == 0, hidden: hidden.includes?(name))
    end,
    audio_inputs: [] of Obsctl::OBS::State::AudioState
  )
  model
end

private def editor_model(names = ["Main", "Utility", "Cam"], hidden = ["Utility"])
  model = preset_model(names, hidden)
  model.scene_preset_editor.active = true
  model
end

private def press(model, character : Char, modifiers = CryTUI::KeyModifiers::None)
  Obsctl::TUI::Input.handle_key(model, CryTUI::KeyEvent.character(character, modifiers))
end

private def press_code(model, code : CryTUI::KeyCode)
  Obsctl::TUI::Input.handle_key(model, CryTUI::KeyEvent.new(code))
end

describe "scene preset editor input" do
  it "opens from the leader sequence" do
    model = preset_model
    press(model, ' ').try(&.kind).should eq(Obsctl::TUI::ActionKind::PendingSequence)
    press(model, ' ').try(&.sequence).should eq("<leader>")

    model.pending_sequence = "<leader>"
    press(model, 'P').try(&.kind).should eq(Obsctl::TUI::ActionKind::OpenScenePresets)
  end

  it "keeps the lowercase leader key free, because `P` is its own token" do
    # `<leader>p` is unbound and `<leader>fp` focuses the OBS profiles panel.
    # Neither must be reachable by pressing the editor's key in lower case.
    model = preset_model
    model.pending_sequence = "<leader>"
    press(model, 'p').try(&.kind).should_not eq(Obsctl::TUI::ActionKind::OpenScenePresets)
  end

  it "toggles the scene under the cursor with `t` and with Space" do
    model = editor_model
    ['t', ' '].each do |character|
      action = press(model, character)
      action.try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsToggleScene)
      # No index: the dispatcher acts on the cursor, so the toggle cannot land
      # on a row the user was not looking at.
      action.try(&.index).should be_nil
    end
  end

  it "navigates with hjkl and with the arrows" do
    model = editor_model
    press(model, 'j').try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNavigateDown)
    press(model, 'k').try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNavigateUp)
    press_code(model, CryTUI::KeyCode::Down).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNavigateDown)
    press_code(model, CryTUI::KeyCode::Up).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNavigateUp)
  end

  it "cycles saved presets with Tab, names with `n`, and saves with Enter" do
    model = editor_model
    press_code(model, CryTUI::KeyCode::Tab).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsCycleNext)
    press_code(model, CryTUI::KeyCode::BackTab).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsCyclePrevious)
    press(model, 'n').try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
    press_code(model, CryTUI::KeyCode::Enter).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsSave)
  end

  it "closes with Esc, with `q`, and with Ctrl-C" do
    model = editor_model
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseScenePresets)
    press(model, 'q').try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseScenePresets)
    press(model, 'c', CryTUI::KeyModifiers::Control).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseScenePresets)
  end

  it "ignores an unbound key rather than closing on a typo" do
    # `z` and `Ctrl-D` do something on the dashboard. In here neither falls
    # through, so a mistyped key costs a keystroke and not the draft.
    model = editor_model
    press(model, 'z').should be_nil
    press(model, 'd', CryTUI::KeyModifiers::Control).should be_nil
  end

  it "takes priority over the scene picker, the command palette and a pending sequence" do
    model = editor_model
    model.scene_picker_active = true
    model.command_palette.active = true
    model.pending_sequence = "<leader>"
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseScenePresets)
  end
end

describe "scene preset naming input" do
  it "types the name a character at a time, `t` included" do
    model = editor_model
    model.scene_preset_editor.naming = true

    action = press(model, 't')
    action.try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNameCharacter)
    action.try(&.character).should eq('t')
    press(model, 'ї').try(&.character).should eq('ї')
  end

  it "edits and submits with the keys the palette line uses" do
    model = editor_model
    model.scene_preset_editor.naming = true

    press_code(model, CryTUI::KeyCode::Backspace).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNameBackspace)
    press(model, 'u', CryTUI::KeyModifiers::Control).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNameClearLine)
    press_code(model, CryTUI::KeyCode::Enter).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNameSubmit)
  end

  it "backs Esc out to the list instead of throwing the draft away" do
    model = editor_model
    model.scene_preset_editor.naming = true
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNameCancel)
    press(model, 'c', CryTUI::KeyModifiers::Control).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsNameCancel)
  end
end

describe "scene preset editor mouse" do
  it "toggles the scene under the pointer and closes on a click outside" do
    model = editor_model
    rect = Obsctl::TUI::ScenePresetsLayout.compute(AREA, model)

    inside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, rect.x + 2, rect.y + 1),
      AREA
    )
    inside.try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePresetsToggleScene)
    inside.try(&.index).should eq(0)

    outside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 0, 0),
      AREA
    )
    outside.try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseScenePresets)
  end

  it "moves the cursor with the wheel" do
    model = editor_model
    wheel = ->(kind : CryTUI::MouseKind) do
      Obsctl::TUI::Input.handle_mouse(
        model,
        CryTUI::MouseEvent.new(kind, CryTUI::MouseButton::None, 10, 10),
        AREA
      ).try(&.kind)
    end
    wheel.call(CryTUI::MouseKind::ScrollDown).should eq(Obsctl::TUI::ActionKind::ScenePresetsNavigateDown)
    wheel.call(CryTUI::MouseKind::ScrollUp).should eq(Obsctl::TUI::ActionKind::ScenePresetsNavigateUp)
  end
end
