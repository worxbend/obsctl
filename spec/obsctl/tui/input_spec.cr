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
end
