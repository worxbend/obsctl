require "../../spec_helper"
require "../../support/scene_profiles"
require "../../../src/obsctl/tui/input"

private AREA = CryTUI::Rect.new(0, 0, 120, 40)

private def profiles(*entries : Tuple(String, Array(String)))
  Obsctl::TUI::SceneProfiles.new(entries.to_a.map { |(name, hidden)| Obsctl::TUI::SceneProfile.new(name, hidden.to_set) })
end

private def list_model(saved = profiles({"streaming", ["Utility"]}, {"editing", [] of String}))
  model = Obsctl::TUI::Model.new
  model.connected_to_daemon = true
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: "Main",
    scenes: ["Main", "Utility", "Cam"].map_with_index do |name, index|
      Obsctl::OBS::State::SceneState.new(name, active: index == 0, hidden: false)
    end,
    audio_inputs: [] of Obsctl::OBS::State::AudioState
  )
  set_scene_profiles(model, saved)
  model.scene_profile_list.active = true
  model
end

private def press(model, character : Char, modifiers = CryTUI::KeyModifiers::None)
  Obsctl::TUI::Input.handle_key(model, CryTUI::KeyEvent.character(character, modifiers))
end

private def press_code(model, code : CryTUI::KeyCode)
  Obsctl::TUI::Input.handle_key(model, CryTUI::KeyEvent.new(code))
end

describe "scene profile list input" do
  it "opens from the lower-case leader key, and the editor still has the upper-case one" do
    model = list_model
    model.scene_profile_list.active = false
    model.pending_sequence = "<leader>"
    press(model, 'p').try(&.kind).should eq(Obsctl::TUI::ActionKind::OpenSceneProfileList)

    model.pending_sequence = "<leader>"
    press(model, 'P').try(&.kind).should eq(Obsctl::TUI::ActionKind::OpenSceneProfiles)
  end

  it "navigates with jk and with the arrows" do
    model = list_model
    press(model, 'j').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
    press(model, 'k').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListNavigateUp)
    press_code(model, CryTUI::KeyCode::Down).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
    press_code(model, CryTUI::KeyCode::Up).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListNavigateUp)
  end

  it "puts each verb on its own letter" do
    model = list_model
    press_code(model, CryTUI::KeyCode::Enter).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListActivate)
    press(model, 'e').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListEdit)
    press(model, 'r').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListRename)
    press(model, 'n').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListNew)
    press(model, 'd').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListDeletePrompt)
  end

  it "closes with Esc, with `q`, and with Ctrl-C" do
    # `q` closes the modal rather than quitting obsctl, the same rule the
    # editor and the picker follow while they are open.
    model = list_model
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfileList)
    press(model, 'q').try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfileList)
    press(model, 'c', CryTUI::KeyModifiers::Control).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfileList)
  end

  it "labels rows by their own number, `0` being show-every-scene" do
    model = list_model
    {'0' => 0, '1' => 1, '2' => 2}.each do |character, index|
      action = press(model, character)
      action.try(&.kind).should eq(Obsctl::TUI::ActionKind::PickSceneProfile)
      action.try(&.index).should eq(index)
    end
  end

  it "ignores a digit no row carries" do
    # Two profiles means rows 0, 1 and 2. A `9` here must not activate the last
    # row: a label that slid onto whatever happened to be nearest would put the
    # wrong profile into effect.
    press(list_model, '9').should be_nil
  end

  it "ignores an unbound key rather than closing on a typo" do
    model = list_model
    press(model, 'z').should be_nil
    press(model, 'd', CryTUI::KeyModifiers::Control).should be_nil
  end

  it "takes priority over the scene picker, the command palette and a pending sequence" do
    model = list_model
    model.scene_picker_active = true
    model.command_palette.active = true
    model.pending_sequence = "<leader>"
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfileList)
  end

  it "yields to the editor, which is the surface opened on top of it" do
    model = list_model
    model.scene_profile_editor.active = true
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfiles)
  end
end

describe "scene profile list delete confirmation" do
  it "confirms on a second `d`" do
    model = list_model
    model.scene_profile_list.confirming = true
    press(model, 'd').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListDeleteConfirm)
  end

  it "cancels on Enter, which means \"use this row\" everywhere else in the list" do
    # Enter is the key a user reaches for to say \"yes, this one\", so letting it
    # confirm would make a mis-armed delete destroy a profile with the most
    # reflexive key on the modal. The hint row asks for `d` and only `d` goes.
    model = list_model
    model.scene_profile_list.confirming = true
    press_code(model, CryTUI::KeyCode::Enter).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListDeleteCancel)
  end

  it "cancels on everything else, navigation and unbound keys included" do
    # A delete cannot be undone, so the arming is deliberately fragile: only
    # the key the hint asks for goes through, and any other press disarms it
    # instead of being swallowed.
    model = list_model
    model.scene_profile_list.confirming = true
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListDeleteCancel)
    press(model, 'j').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListDeleteCancel)
    press(model, 'x').try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListDeleteCancel)
    press(model, 'c', CryTUI::KeyModifiers::Control).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListDeleteCancel)
    press(model, 'd', CryTUI::KeyModifiers::Control).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListDeleteCancel)
  end
end

describe "scene profile list mouse" do
  it "moves the cursor with the wheel" do
    model = list_model
    wheel = ->(kind : CryTUI::MouseKind) do
      Obsctl::TUI::Input.handle_mouse(
        model,
        CryTUI::MouseEvent.new(kind, CryTUI::MouseButton::None, 10, 10),
        AREA
      ).try(&.kind)
    end
    wheel.call(CryTUI::MouseKind::ScrollDown).should eq(Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
    wheel.call(CryTUI::MouseKind::ScrollUp).should eq(Obsctl::TUI::ActionKind::SceneProfileListNavigateUp)
  end

  it "spends a click on disarming a delete rather than on the row under it" do
    # The second press of a two-press delete must be a deliberate one. A stray
    # click while the prompt is up cancels and does nothing else.
    model = list_model
    model.scene_profile_list.confirming = true
    Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 10, 10),
      AREA
    ).try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListDeleteCancel)
  end
end
