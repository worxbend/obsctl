require "../../spec_helper"
require "../../../src/obsctl/tui/input"

private AREA = CryTUI::Rect.new(0, 0, 120, 40)

# Three scenes, one of which OBS reports as hidden. The editor is the only
# surface that lists that third row, so every example here needs it present.
private def profile_model(names = ["Main", "Utility", "Cam"], hidden = ["Utility"])
  model = Obsctl::TUI::Model.new
  model.connected_to_daemon = true
  model.snapshot = Obsctl::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: names.first?,
    scenes: names.map_with_index do |name, index|
      Obsctl::State::SceneState.new(name, active: index == 0, hidden: hidden.includes?(name))
    end,
    audio_inputs: [] of Obsctl::State::AudioState
  )
  model
end

private def editor_model(names = ["Main", "Utility", "Cam"], hidden = ["Utility"])
  model = profile_model(names, hidden)
  model.scene_profile_editor.active = true
  model
end

private def press(model, character : Char, modifiers = CryTUI::KeyModifiers::None)
  Obsctl::TUI::Input.handle_key(model, CryTUI::KeyEvent.character(character, modifiers))
end

private def press_code(model, code : CryTUI::KeyCode)
  Obsctl::TUI::Input.handle_key(model, CryTUI::KeyEvent.new(code))
end

describe "scene profile editor input" do
  it "opens from the leader sequence" do
    model = profile_model
    press(model, ' ').try(&.kind).should eq(Obsctl::TUI::ActionKind::PendingSequence)
    press(model, ' ').try(&.sequence).should eq("<leader>")

    model.pending_sequence = "<leader>"
    press(model, 'P').try(&.kind).should eq(Obsctl::TUI::ActionKind::OpenSceneProfiles)
  end

  it "gives the lower-case leader key to the profile list, not to the editor" do
    # `Keymap.token` keeps the case of a key, so `p` and `P` are two tokens:
    # `<leader>p` opens the list of saved profiles and `<leader>P` opens this
    # editor. `<leader>fp`, which focuses the OBS Profiles panel, is a third
    # thing again and must stay reachable.
    model = profile_model
    model.pending_sequence = "<leader>"
    press(model, 'p').try(&.kind).should eq(Obsctl::TUI::ActionKind::OpenSceneProfileList)

    model.pending_sequence = "<leader>f"
    press(model, 'p').try(&.kind).should eq(Obsctl::TUI::ActionKind::FocusProfiles)
  end

  it "toggles the scene under the cursor with `t` and with Space" do
    model = editor_model
    ['t', ' '].each do |character|
      action = press(model, character)
      action.try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesToggleScene)
      # No index: the dispatcher acts on the cursor, so the toggle cannot land
      # on a row the user was not looking at.
      action.try(&.index).should be_nil
    end
  end

  it "navigates with hjkl and with the arrows" do
    model = editor_model
    press(model, 'j').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNavigateDown)
    press(model, 'k').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNavigateUp)
    press_code(model, CryTUI::KeyCode::Down).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNavigateDown)
    press_code(model, CryTUI::KeyCode::Up).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNavigateUp)
  end

  it "cycles saved profiles with Tab, names with `n`, and saves with Enter" do
    model = editor_model
    press_code(model, CryTUI::KeyCode::Tab).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesCycleNext)
    press_code(model, CryTUI::KeyCode::BackTab).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesCyclePrevious)
    press(model, 'n').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
    press_code(model, CryTUI::KeyCode::Enter).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesSave)
  end

  it "closes with Esc, with `q`, and with Ctrl-C" do
    model = editor_model
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfiles)
    press(model, 'q').try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfiles)
    press(model, 'c', CryTUI::KeyModifiers::Control).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfiles)
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
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfiles)
  end
end

describe "scene profile naming input" do
  it "types the name a character at a time, `t` included" do
    model = editor_model
    model.scene_profile_editor.naming = true

    action = press(model, 't')
    action.try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNameCharacter)
    action.try(&.character).should eq('t')
    press(model, 'ї').try(&.character).should eq('ї')
  end

  it "edits and submits with the keys the palette line uses" do
    model = editor_model
    model.scene_profile_editor.naming = true

    press_code(model, CryTUI::KeyCode::Backspace).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNameBackspace)
    press(model, 'u', CryTUI::KeyModifiers::Control).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNameClearLine)
    press_code(model, CryTUI::KeyCode::Enter).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)
  end

  it "backs Esc out to the list instead of throwing the draft away" do
    model = editor_model
    model.scene_profile_editor.naming = true
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNameCancel)
    press(model, 'c', CryTUI::KeyModifiers::Control).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesNameCancel)
  end
end

describe "scene profile editor mouse" do
  it "toggles the scene under the pointer and closes on a click outside" do
    model = editor_model
    rect = Obsctl::TUI::SceneProfilesLayout.compute(AREA, model)

    inside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, rect.x + 2, rect.y + 1),
      AREA
    )
    inside.try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfilesToggleScene)
    inside.try(&.index).should eq(0)

    outside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 0, 0),
      AREA
    )
    outside.try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfiles)
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
    wheel.call(CryTUI::MouseKind::ScrollDown).should eq(Obsctl::TUI::ActionKind::SceneProfilesNavigateDown)
    wheel.call(CryTUI::MouseKind::ScrollUp).should eq(Obsctl::TUI::ActionKind::SceneProfilesNavigateUp)
  end

  # While the name field is open the box is a text field, not a list. A click
  # that toggled a row would change the draft under a reader who is looking at
  # a name being typed, with nothing on screen reporting it.
  it "ignores the pointer entirely while a name is being typed" do
    model = editor_model
    model.scene_profile_editor.naming = true
    model.scene_profile_editor.name_input = "streaming"
    rect = Obsctl::TUI::SceneProfilesLayout.compute(AREA, model)

    click = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, rect.x + 2, rect.y + 1),
      AREA
    )
    click.should be_nil

    scroll = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::ScrollDown, CryTUI::MouseButton::None, 10, 10),
      AREA
    )
    scroll.should be_nil
  end
end
