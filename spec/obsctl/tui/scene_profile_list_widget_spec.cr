require "../../spec_helper"
require "../../support/scene_profiles"
require "../../../src/obsctl/tui/input"
require "../../../src/obsctl/tui/widgets/scene_profile_list"

private AREA = CryTUI::Rect.new(0, 0, 120, 40)

private def list_widget_model(active : String? = "streaming", names = ["streaming", "recording"])
  model = Obsctl::TUI::Model.new(theme: Obsctl::TUI::Theme::NORD)
  model.connected_to_daemon = true
  model.snapshot = scene_profile_spec_snapshot
  profiles = names.map_with_index do |name, index|
    Obsctl::TUI::SceneProfile.new(name, Array.new(index + 1) { |slot| "Utility #{slot}" }.to_set)
  end
  set_scene_profiles(model, Obsctl::TUI::SceneProfiles.new(profiles, active))
  model
end

private def open_profile_list(model, cursor = 0, confirming = false)
  model.scene_profile_list = Obsctl::TUI::SceneProfileListState.new(active: true, cursor: cursor, confirming: confirming)
  model
end

private def render_list(model, width = 120, height = 40)
  buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, width, height))
  Obsctl::TUI::Widgets::SceneProfileList.render(buffer.area, buffer, model)
  buffer
end

private def list_rendered_text(buffer : CryTUI::Buffer)
  buffer.lines.join("\n")
end

# The cell the widget drew the first letter of a row's name in, found through
# the same `row_text` the box was measured against rather than by hunting the
# buffer for a letter -- the title carries most of them too.
private def list_name_cell(buffer : CryTUI::Buffer, model, rect : CryTUI::Rect, entry)
  offset = Obsctl::TUI::SceneProfileListLayout.row_text(model, entry).index!(entry.name)
  buffer[rect.x + 1 + offset, rect.y + 1 + entry.index]
end

describe Obsctl::TUI::Widgets::SceneProfileList do
  it "draws nothing at all while the list is closed" do
    list_rendered_text(render_list(list_widget_model())).strip.should be_empty
  end

  it "offers `show every scene` first, then every saved profile in order" do
    text = list_rendered_text(render_list(open_profile_list(list_widget_model())))

    text.should contain("Scene profiles")
    # Turning filtering off is a row you can see and press, not a gesture: a
    # reader who cannot find their scenes again is stuck with a dashboard that
    # looks broken.
    text.should contain(Obsctl::TUI::SceneProfileList::SHOW_EVERY_SCENE)
    text.should contain("streaming")
    text.should contain("recording")
    text.index!("streaming").should be < text.index!("recording")
  end

  it "labels each row with its own number and says how many scenes it hides" do
    model = open_profile_list(list_widget_model())
    entries = model.scene_profile_list_entries

    entries.map(&.label).should eq(['0', '1', '2'])
    # Row number and label are the same character, so the digit that activates
    # a row is the one already printed beside it.
    Obsctl::TUI::SceneProfileListLayout.row_text(model, entries[1]).should contain("hides 1")
    Obsctl::TUI::SceneProfileListLayout.row_text(model, entries[2]).should contain("hides 2")
    # Nothing for the row that hides nothing by definition, which would
    # otherwise read as a profile that happens to hide zero scenes.
    Obsctl::TUI::SceneProfileListLayout.row_text(model, entries[0]).should_not contain("hides")

    text = list_rendered_text(render_list(model))
    text.should contain("hides 1")
    text.should contain("hides 2")
  end

  it "marks the profile in effect without changing the width of the row" do
    model = open_profile_list(list_widget_model())
    entries = model.scene_profile_list_entries
    in_effect = entries.find! { |entry| entry.name == "streaming" }
    other = entries.find! { |entry| entry.name == "recording" }

    Obsctl::TUI::SceneProfileListLayout.marker(model, true).should_not eq(Obsctl::TUI::SceneProfileListLayout.marker(model, false))
    # Same name length and the same hidden-scene count either side, so any
    # difference in width would be the marker's -- and a marker that changed
    # width would move the box the hit test measures against.
    active_row = Obsctl::TUI::SceneProfileListLayout.row_text(model, in_effect)
    idle_row = Obsctl::TUI::SceneProfileListLayout.row_text(model, other).sub("recording", "streaming")
    CryTUI::TextWidth.width(active_row).should eq(CryTUI::TextWidth.width(idle_row))

    buffer = render_list(model)
    rect = Obsctl::TUI::SceneProfileListLayout.compute(AREA, model)
    list_name_cell(buffer, model, rect, in_effect).style.foreground.should eq(Obsctl::TUI::Theme::NORD.success)
    list_name_cell(buffer, model, rect, other).style.foreground.should_not eq(Obsctl::TUI::Theme::NORD.success)
  end

  it "marks `show every scene` when no profile is in effect" do
    model = open_profile_list(list_widget_model(active: nil))
    entries = model.scene_profile_list_entries

    entries.first.active.should be_true
    entries.any? { |entry| entry.profile && entry.active }.should be_false
    list_rendered_text(render_list(model)).should contain(Obsctl::TUI::SceneProfileListLayout.marker(model, true))
  end

  it "keeps every verb on a row of its own" do
    text = list_rendered_text(render_list(open_profile_list(list_widget_model())))

    text.should contain("e edit")
    text.should contain("r rename")
    text.should contain("n new")
    text.should contain("d delete")
    text.should contain("esc close")
  end

  it "asks the question in the warning colour once a delete is armed" do
    model = open_profile_list(list_widget_model(), cursor: 1, confirming: true)
    buffer = render_list(model)
    text = list_rendered_text(buffer)

    # The row names the profile at stake, because the second press cannot be
    # taken back and the reader's cursor is not what they are looking at.
    text.should contain("delete")
    text.should contain("streaming")
    text.should contain("d confirm")
    text.should contain("esc cancel")
    # The ordinary keys are gone: the two sets never share the row, or a reader
    # skimming it would still see "n new" while `d` was about to delete.
    text.should_not contain("r rename")

    rect = Obsctl::TUI::SceneProfileListLayout.compute(AREA, model)
    row = Obsctl::TUI::SceneProfileListLayout.hint_row(rect)
    # From inside the border, whose own colour would otherwise answer first.
    painted = ((rect.x + 1)...(rect.right - 1)).map { |column| buffer[column, row] }.find! { |cell| cell.symbol != " " }
    painted.style.foreground.should eq(Obsctl::TUI::Theme::NORD.warning)
  end

  it "does not change width when a delete is armed" do
    model = list_widget_model()
    browsing = Obsctl::TUI::SceneProfileListLayout.compute(AREA, open_profile_list(model, cursor: 1))
    armed = Obsctl::TUI::SceneProfileListLayout.compute(AREA, open_profile_list(model, cursor: 1, confirming: true))

    # Arming a delete must not resize the box, or the row the reader is about
    # to press a second time moves out from under the pointer.
    armed.should eq(browsing)
  end

  it "falls back to plain words on a terminal without icons" do
    model = open_profile_list(list_widget_model())
    model.show_icons = false
    model.advanced_ui = false
    text = list_rendered_text(render_list(model))

    text.should contain("Enter use")
    text.should contain("Esc close")
    text.should_not contain("🗂")
    text.should_not contain("↵")
  end

  it "keeps the way out on screen whatever a profile is called" do
    long = "streaming-and-recording-and-everything-else-at-once"
    model = open_profile_list(list_widget_model(active: long, names: [long, "recording"]))

    {AREA, CryTUI::Rect.new(0, 0, 80, 24), CryTUI::Rect.new(0, 0, 40, 12)}.each do |area|
      rect = Obsctl::TUI::SceneProfileListLayout.compute(area, model)
      rect.width.should be <= Obsctl::TUI::SceneProfileListLayout::MAX_WIDTH

      text = list_rendered_text(render_list(model, width: area.width, height: area.height))
      text.should contain("close")
      text.should contain("Scene profiles")
    end
  end

  it "stays off a terminal too small to be worth taking over" do
    model = open_profile_list(list_widget_model())
    Obsctl::TUI::SceneProfileListLayout.compute(CryTUI::Rect.new(0, 0, 20, 6), model).empty?.should be_true
    list_rendered_text(render_list(model, width: 20, height: 6)).strip.should be_empty
  end
end

describe "scene profile list mouse" do
  it "activates the row under the pointer and closes on a click outside" do
    model = open_profile_list(list_widget_model())
    rect = Obsctl::TUI::SceneProfileListLayout.compute(AREA, model)

    inside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, rect.x + 2, rect.y + 2),
      AREA
    )
    inside.try(&.kind).should eq(Obsctl::TUI::ActionKind::PickSceneProfile)
    inside.try(&.index).should eq(1)

    outside = Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 0, 0),
      AREA
    )
    outside.try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfileList)
  end

  it "treats the hint row as chrome rather than as the profile it lines up with" do
    model = open_profile_list(list_widget_model())
    rect = Obsctl::TUI::SceneProfileListLayout.compute(AREA, model)
    hint_row = Obsctl::TUI::SceneProfileListLayout.hint_row(rect)

    # The row is inside the border, so without the list's own box the hit test
    # would resolve it to whichever profile the list scrolled under it.
    Obsctl::TUI::HitTest.scene_profile_list_index(model, AREA, rect.x + 2, hint_row).should be_nil
    Obsctl::TUI::Input.handle_mouse(
      model,
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, rect.x + 2, hint_row),
      AREA
    ).try(&.kind).should eq(Obsctl::TUI::ActionKind::CloseSceneProfileList)
  end

  it "walks the list with the wheel" do
    model = open_profile_list(list_widget_model())
    rect = Obsctl::TUI::SceneProfileListLayout.compute(AREA, model)

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
    up.try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListNavigateUp)
    down.try(&.kind).should eq(Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
  end
end
