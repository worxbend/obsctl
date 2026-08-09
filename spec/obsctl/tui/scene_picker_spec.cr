require "../../spec_helper"
require "../../../src/obsctl/tui/dispatcher"
require "../../../src/obsctl/tui/input"
require "../../../src/obsctl/tui/widgets/scene_picker"

private AREA = CryTUI::Rect.new(0, 0, 120, 40)

private def scene_states(names : Array(String), shortcuts = {} of String => String)
  names.map_with_index do |name, index|
    Obsctl::OBS::State::SceneState.new(name, shortcut: shortcuts[name]?, active: index == 0)
  end
end

private def picker_model(names = ["Main", "Cam", "BRB"], shortcuts = {} of String => String)
  model = Obsctl::TUI::Model.new
  model.connected_to_daemon = true
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: names.first?,
    scenes: scene_states(names, shortcuts),
    audio_inputs: [] of Obsctl::OBS::State::AudioState
  )
  model
end

private def picker_dispatcher(model)
  sent = [] of Obsctl::IPC::CommandPayload
  sender = ->(payload : Obsctl::IPC::CommandPayload) do
    sent << payload
    Obsctl::IPC::Response.new("test", true, JSON.parse(%({"message":"ok"})))
  end
  {sent, Obsctl::TUI::Dispatcher.new(model, sender)}
end

private def press(model, character : Char)
  Obsctl::TUI::Input.handle_key(model, CryTUI::KeyEvent.character(character))
end

private def press_code(model, code : CryTUI::KeyCode)
  Obsctl::TUI::Input.handle_key(model, CryTUI::KeyEvent.new(code))
end

private def labels(model)
  model.scene_picker_entries.map(&.label)
end

describe Obsctl::TUI::ScenePicker do
  it "labels scenes with digits and then letters, in list order" do
    model = picker_model(["Main", "Cam", "BRB"])
    labels(model).should eq(['1', '2', '3'])
  end

  it "lets a configured single-character shortcut claim its key before the sequence" do
    # `Cam` is configured `shortcut: 1`, which the scenes panel already shows as
    # `[1]`. It keeps that key, so the automatic labels skip it entirely.
    model = picker_model(["Main", "Cam", "BRB"], {"Cam" => "1"})
    labels(model).should eq(['2', '1', '3'])
  end

  it "ignores multi-character and out-of-alphabet shortcuts, which cannot be one press" do
    model = picker_model(["Main", "Cam", "BRB"], {"Cam" => "brb", "BRB" => "!"})
    labels(model).should eq(['1', '2', '3'])
  end

  it "runs digits into letters and leaves scenes past the alphabet unlabelled" do
    names = (1..40).map { |number| "Scene #{number}" }
    entries = Obsctl::TUI::ScenePicker.entries(scene_states(names))
    entries[0].label.should eq('1')
    entries[8].label.should eq('9')
    # Ten scenes in the digits run out and the letters take over.
    entries[9].label.should eq('a')
    entries[34].label.should eq('z')
    # Thirty-five labels exist; everything after them is arrow-key territory.
    entries[35].label.should be_nil
    entries[39].label.should be_nil
  end

  it "matches labels case-insensitively, so Shift held over a letter still lands" do
    names = (1..12).map { |number| "Scene #{number}" }
    entries = Obsctl::TUI::ScenePicker.entries(scene_states(names))
    Obsctl::TUI::ScenePicker.index_for(entries, 'a').should eq(9)
    Obsctl::TUI::ScenePicker.index_for(entries, 'A').should eq(9)
    Obsctl::TUI::ScenePicker.index_for(entries, '~').should be_nil
  end
end

describe "scene picker input" do
  it "opens from the leader sequence" do
    model = picker_model
    Obsctl::TUI::Input.handle_key(model, CryTUI::KeyEvent.character(' ')).try(&.kind)
      .should eq(Obsctl::TUI::ActionKind::PendingSequence)
    model.pending_sequence = "<leader>"
    press(model, 's').try(&.kind).should eq(Obsctl::TUI::ActionKind::OpenScenePicker)
  end

  it "captures keys that are dashboard bindings, so a label reaches its scene" do
    # `q` quits and `a` focuses audio on the dashboard. Inside the picker both
    # are labels; if they fell through, the picker would be unusable. Thirty
    # scenes is enough for the labels to reach `q`, which sits at `a` plus 16.
    names = (1..30).map { |number| "Scene #{number}" }
    model = picker_model(names)
    model.scene_picker_active = true

    press(model, 'q').try(&.kind).should eq(Obsctl::TUI::ActionKind::PickScene)
    press(model, 'q').try(&.index).should eq(Obsctl::TUI::ScenePicker.index_for(model.scene_picker_entries, 'q'))
    press(model, 'a').try(&.kind).should eq(Obsctl::TUI::ActionKind::PickScene)
  end

  it "ignores an unlabelled key rather than closing on a typo" do
    model = picker_model(["Main", "Cam"])
    model.scene_picker_active = true
    press(model, 'z').should be_nil
  end

  it "navigates with the arrows and leaves with Esc" do
    model = picker_model
    model.scene_picker_active = true
    press_code(model, CryTUI::KeyCode::Down).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePickerNavigateDown)
    press_code(model, CryTUI::KeyCode::Up).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePickerNavigateUp)
    press_code(model, CryTUI::KeyCode::Enter).try(&.kind).should eq(Obsctl::TUI::ActionKind::ScenePickerActivate)
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseScenePicker)
  end

  it "takes priority over the command palette and a pending sequence" do
    model = picker_model
    model.scene_picker_active = true
    model.command_palette.active = true
    model.pending_sequence = "<leader>"
    press_code(model, CryTUI::KeyCode::Escape).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseScenePicker)
  end
end

describe "scene picker mouse" do
  it "picks the scene under the pointer and closes on a click outside" do
    model = picker_model
    model.scene_picker_active = true
    rect = Obsctl::TUI::ScenePickerLayout.compute(AREA, model)

    inside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, rect.x + 2, rect.y + 1),
      AREA
    )
    inside.try(&.kind).should eq(Obsctl::TUI::ActionKind::PickScene)
    inside.try(&.index).should eq(0)

    outside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 0, 0),
      AREA
    )
    outside.try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseScenePicker)
  end
end

describe "scene picker dispatch" do
  it "opens on the live scene rather than the top of the list" do
    model = picker_model(["Main", "Cam", "BRB"])
    model.snapshot = model.snapshot.not_nil!.copy_with(scenes: [
      Obsctl::OBS::State::SceneState.new("Main"),
      Obsctl::OBS::State::SceneState.new("Cam", active: true),
      Obsctl::OBS::State::SceneState.new("BRB"),
    ])
    _, dispatcher = picker_dispatcher(model)
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenScenePicker))
    model.scene_picker_active.should be_true
    model.scene_picker_cursor.should eq(1)
  end

  it "refuses to open with no scenes, because it would swallow keys for nothing" do
    model = picker_model([] of String)
    _, dispatcher = picker_dispatcher(model)
    outcome = dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenScenePicker))
    model.scene_picker_active.should be_false
    outcome.message.should eq("no scenes to switch to")
  end

  it "switches scene, closes, and moves the dashboard cursor to match" do
    model = picker_model(["Main", "Cam", "BRB"])
    sent, dispatcher = picker_dispatcher(model)
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenScenePicker))
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::PickScene, index: 2))

    model.scene_picker_active.should be_false
    model.scene_cursor.should eq(2)
    sent.map(&.name).should eq(["set_scene"])
    sent.first.target.should eq("BRB")
  end

  it "leaves the dashboard untouched when the picker is closed without picking" do
    model = picker_model(["Main", "Cam", "BRB"])
    model.scene_cursor = 1
    sent, dispatcher = picker_dispatcher(model)
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenScenePicker))
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::CloseScenePicker))

    model.scene_picker_active.should be_false
    model.scene_cursor.should eq(1)
    sent.should be_empty
  end

  it "activates the scene under the cursor on Enter" do
    model = picker_model(["Main", "Cam", "BRB"])
    sent, dispatcher = picker_dispatcher(model)
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenScenePicker))
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::ScenePickerNavigateDown))
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::ScenePickerActivate))
    sent.first.target.should eq("Cam")
  end

  it "clamps the cursor at both ends instead of wrapping" do
    model = picker_model(["Main", "Cam"])
    _, dispatcher = picker_dispatcher(model)
    dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::OpenScenePicker))
    3.times { dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::ScenePickerNavigateUp)) }
    model.scene_picker_cursor.should eq(0)
    5.times { dispatcher.handle(Obsctl::TUI::Action.new(Obsctl::TUI::ActionKind::ScenePickerNavigateDown)) }
    model.scene_picker_cursor.should eq(1)
  end
end

describe Obsctl::TUI::Widgets::ScenePicker do
  it "draws each scene beside the key that switches to it" do
    model = picker_model(["Main", "Cam", "BRB"])
    model.scene_picker_active = true
    buffer = CryTUI::Buffer.new(AREA)
    Obsctl::TUI::Widgets::ScenePicker.render(AREA, buffer, model)
    text = buffer.lines.join("\n")

    text.should contain("Switch scene")
    text.should contain("1  Main")
    text.should contain("2  Cam")
    text.should contain("3  BRB")
  end

  it "sizes the box to its own title, so the way out stays legible" do
    # Short scene names would otherwise leave the box narrower than its title
    # and truncate the "esc close" hint -- the only way out of a modal.
    model = picker_model(["A", "B"])
    model.scene_picker_active = true
    buffer = CryTUI::Buffer.new(AREA)
    Obsctl::TUI::Widgets::ScenePicker.render(AREA, buffer, model)
    buffer.lines.join("\n").should contain("esc close")
  end

  it "renders in plain terminals without the icons" do
    model = picker_model(["Main", "Cam"])
    model.scene_picker_active = true
    model.advanced_ui = false
    model.show_icons = false
    buffer = CryTUI::Buffer.new(AREA)
    Obsctl::TUI::Widgets::ScenePicker.render(AREA, buffer, model)
    text = buffer.lines.join("\n")
    text.should contain("Switch scene")
    text.should contain("Esc close")
    text.should contain("1  Main")
  end

  it "stays off a terminal too small to show a usable box" do
    model = picker_model(["Main", "Cam"])
    model.scene_picker_active = true
    tiny = CryTUI::Rect.new(0, 0, 20, 6)
    buffer = CryTUI::Buffer.new(tiny)
    Obsctl::TUI::Widgets::ScenePicker.render(tiny, buffer, model)
    buffer.lines.join.strip.should be_empty
  end

  it "draws nothing while it is closed" do
    model = picker_model
    buffer = CryTUI::Buffer.new(AREA)
    Obsctl::TUI::Widgets::ScenePicker.render(AREA, buffer, model)
    buffer.lines.join.strip.should be_empty
  end
end
