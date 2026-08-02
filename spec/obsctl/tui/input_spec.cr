require "../../spec_helper"
require "../../../src/obsctl/tui/input"

private def tui_key(code : CryTUI::KeyCode, modifiers = CryTUI::KeyModifiers::None)
  CryTUI::KeyEvent.new(code, modifiers: modifiers)
end

private def tui_char(character : Char, modifiers = CryTUI::KeyModifiers::None)
  CryTUI::KeyEvent.character(character, modifiers)
end

private def action_kind(model, key)
  Obsctl::TUI::Input.handle_key(model, key).try(&.kind)
end

describe Obsctl::TUI::Input do
  it "maps global commands and panel focus" do
    model = Obsctl::TUI::Model.new
    action_kind(model, tui_char('q')).should eq(Obsctl::TUI::ActionKind::Quit)
    action_kind(model, tui_char('/')).should eq(Obsctl::TUI::ActionKind::OpenPalette)
    action_kind(model, tui_char('a')).should eq(Obsctl::TUI::ActionKind::FocusAudio)
    action_kind(model, CryTUI::KeyEvent.new(CryTUI::KeyCode::Function, function: 2)).should eq(Obsctl::TUI::ActionKind::OpenSettings)
  end

  it "gives control pane navigation precedence over audio volume" do
    model = Obsctl::TUI::Model.new
    model.focus = Obsctl::TUI::FocusPanel::Audio
    action_kind(model, tui_key(CryTUI::KeyCode::Left)).should eq(Obsctl::TUI::ActionKind::VolumeDown)
    action_kind(model, tui_key(CryTUI::KeyCode::Left, CryTUI::KeyModifiers::Control)).should eq(Obsctl::TUI::ActionKind::FocusPaneLeft)
    action_kind(model, tui_char('h', CryTUI::KeyModifiers::Control)).should eq(Obsctl::TUI::ActionKind::FocusPaneLeft)
  end

  it "routes palette keys before global bindings" do
    model = Obsctl::TUI::Model.new
    model.command_palette.active = true
    action_kind(model, tui_char('q')).should eq(Obsctl::TUI::ActionKind::PaletteCharacter)
    action = Obsctl::TUI::Input.handle_key(model, tui_char('ї')).not_nil!
    action.kind.should eq(Obsctl::TUI::ActionKind::PaletteCharacter)
    action.character.should eq('ї')
    action_kind(model, tui_key(CryTUI::KeyCode::Tab)).should eq(Obsctl::TUI::ActionKind::CompleteNext)
    action_kind(model, tui_key(CryTUI::KeyCode::Escape)).should eq(Obsctl::TUI::ActionKind::ClosePalette)
  end

  it "routes settings keys without quitting the application" do
    model = Obsctl::TUI::Model.new
    model.view = Obsctl::TUI::View::Settings
    action_kind(model, tui_char('q')).should eq(Obsctl::TUI::ActionKind::CloseSettings)
    action_kind(model, tui_key(CryTUI::KeyCode::Down)).should eq(Obsctl::TUI::ActionKind::SettingsNavigateDown)
    action_kind(model, tui_key(CryTUI::KeyCode::Enter)).should eq(Obsctl::TUI::ActionKind::ApplySettingsTheme)
  end

  it "activates the selected resource based on panel focus" do
    model = Obsctl::TUI::Model.new
    model.focus = Obsctl::TUI::FocusPanel::Scenes
    action_kind(model, tui_key(CryTUI::KeyCode::Enter)).should eq(Obsctl::TUI::ActionKind::ActivateScene)
    model.focus = Obsctl::TUI::FocusPanel::Profiles
    action_kind(model, tui_key(CryTUI::KeyCode::Enter)).should eq(Obsctl::TUI::ActionKind::ActivateProfile)
  end

  it "opens the palette with the key that was pressed" do
    model = Obsctl::TUI::Model.new
    colon = Obsctl::TUI::Input.handle_key(model, tui_char(':')).not_nil!
    colon.kind.should eq(Obsctl::TUI::ActionKind::OpenPalette)
    colon.character.should eq(':')
    Obsctl::TUI::Input.handle_key(model, tui_char('/')).not_nil!.character.should eq('/')
  end

  it "holds a prefix key until the sequence resolves" do
    model = Obsctl::TUI::Model.new
    pending = Obsctl::TUI::Input.handle_key(model, tui_char('g')).not_nil!
    pending.kind.should eq(Obsctl::TUI::ActionKind::PendingSequence)
    pending.sequence.should eq("g")

    model.pending_sequence = "g"
    action_kind(model, tui_char('g')).should eq(Obsctl::TUI::ActionKind::NavigateTop)
  end

  it "walks the leader menu one key at a time" do
    model = Obsctl::TUI::Model.new
    leader = Obsctl::TUI::Input.handle_key(model, tui_char(' ')).not_nil!
    leader.sequence.should eq("<leader>")

    model.pending_sequence = "<leader>"
    group = Obsctl::TUI::Input.handle_key(model, tui_char('f')).not_nil!
    group.kind.should eq(Obsctl::TUI::ActionKind::PendingSequence)
    group.sequence.should eq("<leader>f")

    model.pending_sequence = "<leader>f"
    action_kind(model, tui_char('a')).should eq(Obsctl::TUI::ActionKind::FocusAudio)
  end

  it "cancels a sequence on escape or an unbound continuation" do
    model = Obsctl::TUI::Model.new
    model.pending_sequence = "<leader>"
    action_kind(model, tui_key(CryTUI::KeyCode::Escape)).should eq(Obsctl::TUI::ActionKind::ClearSequence)
    # `z` is not bound under the leader, so it cancels rather than falling
    # through to whatever `z` would mean on its own.
    action_kind(model, tui_char('z')).should eq(Obsctl::TUI::ActionKind::ClearSequence)
  end

  it "maps the vim motions that need no prefix" do
    model = Obsctl::TUI::Model.new
    action_kind(model, tui_char('G')).should eq(Obsctl::TUI::ActionKind::NavigateBottom)
    action_kind(model, tui_char('d', CryTUI::KeyModifiers::Control)).should eq(Obsctl::TUI::ActionKind::NavigateHalfPageDown)
    action_kind(model, tui_char('u', CryTUI::KeyModifiers::Control)).should eq(Obsctl::TUI::ActionKind::NavigateHalfPageUp)
    action_kind(model, tui_key(CryTUI::KeyCode::PageDown)).should eq(Obsctl::TUI::ActionKind::NavigateHalfPageDown)
    action_kind(model, tui_key(CryTUI::KeyCode::Home)).should eq(Obsctl::TUI::ActionKind::NavigateTop)
  end

  it "moves between panes with the window prefix as well as control" do
    model = Obsctl::TUI::Model.new
    window = Obsctl::TUI::Input.handle_key(model, tui_char('w', CryTUI::KeyModifiers::Control)).not_nil!
    window.sequence.should eq("<C-w>")

    model.pending_sequence = "<C-w>"
    action_kind(model, tui_char('l')).should eq(Obsctl::TUI::ActionKind::FocusPaneRight)
  end

  it "edits the palette line with the vim command-line keys" do
    model = Obsctl::TUI::Model.new
    model.command_palette.active = true
    action_kind(model, tui_char('u', CryTUI::KeyModifiers::Control)).should eq(Obsctl::TUI::ActionKind::PaletteClearLine)
    action_kind(model, tui_char('w', CryTUI::KeyModifiers::Control)).should eq(Obsctl::TUI::ActionKind::PaletteDeleteWord)
    action_kind(model, tui_char('n', CryTUI::KeyModifiers::Control)).should eq(Obsctl::TUI::ActionKind::CompleteNext)
    action_kind(model, tui_char('p', CryTUI::KeyModifiers::Control)).should eq(Obsctl::TUI::ActionKind::CompletePrevious)
  end

  it "keeps a pending sequence from reaching the palette or settings views" do
    model = Obsctl::TUI::Model.new
    model.pending_sequence = "<leader>"
    model.command_palette.active = true
    action_kind(model, tui_char('q')).should eq(Obsctl::TUI::ActionKind::PaletteCharacter)
  end
end
