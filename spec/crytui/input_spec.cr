require "../spec_helper"
require "../../src/crytui"

describe CryTUI::InputParser do
  it "parses printable UTF-8, control keys, navigation, and function keys" do
    parser = CryTUI::InputParser.new
    events = parser.feed("ї\u0003\e[A\e[1;5C\eOQ")

    events.should eq([
      CryTUI::KeyEvent.character('ї'),
      CryTUI::KeyEvent.character('c', CryTUI::KeyModifiers::Control),
      CryTUI::KeyEvent.new(CryTUI::KeyCode::Up),
      CryTUI::KeyEvent.new(CryTUI::KeyCode::Right, modifiers: CryTUI::KeyModifiers::Control),
      CryTUI::KeyEvent.new(CryTUI::KeyCode::Function, function: 2),
    ] of CryTUI::InputEvent)
  end

  it "retains partial escape sequences between reads" do
    parser = CryTUI::InputParser.new
    parser.feed("\e[1;").should be_empty
    parser.feed("5D").should eq([CryTUI::KeyEvent.new(CryTUI::KeyCode::Left, modifiers: CryTUI::KeyModifiers::Control)] of CryTUI::InputEvent)
  end

  it "emits bracketed paste as one event across chunks" do
    parser = CryTUI::InputParser.new
    parser.feed("\e[200~hello").should be_empty
    parser.feed("\nworld\e[20").should be_empty
    parser.feed("1~").should eq([CryTUI::PasteEvent.new("hello\nworld")] of CryTUI::InputEvent)
  end

  it "flushes an ambiguous lone escape" do
    parser = CryTUI::InputParser.new
    parser.feed("\e").should be_empty
    parser.flush_escape.should eq([CryTUI::KeyEvent.new(CryTUI::KeyCode::Escape)] of CryTUI::InputEvent)
  end
end
