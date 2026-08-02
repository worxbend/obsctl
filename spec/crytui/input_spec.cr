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

describe CryTUI::InputParser do
  it "parses SGR mouse presses, releases, and drags into zero-based cells" do
    parser = CryTUI::InputParser.new

    # Terminals count rows and columns from one; callers work in buffer space.
    parser.feed("\e[<0;12;5M").should eq([
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 11, 4),
    ] of CryTUI::InputEvent)
    parser.feed("\e[<0;12;5m").should eq([
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Release, CryTUI::MouseButton::Left, 11, 4),
    ] of CryTUI::InputEvent)
    parser.feed("\e[<32;13;6M").should eq([
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Drag, CryTUI::MouseButton::Left, 12, 5),
    ] of CryTUI::InputEvent)
    parser.feed("\e[<2;1;1M").should eq([
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Right, 0, 0),
    ] of CryTUI::InputEvent)
  end

  it "parses wheel reports and their modifiers" do
    parser = CryTUI::InputParser.new

    parser.feed("\e[<64;4;9M").should eq([
      CryTUI::MouseEvent.new(CryTUI::MouseKind::ScrollUp, CryTUI::MouseButton::None, 3, 8),
    ] of CryTUI::InputEvent)
    parser.feed("\e[<65;4;9M").should eq([
      CryTUI::MouseEvent.new(CryTUI::MouseKind::ScrollDown, CryTUI::MouseButton::None, 3, 8),
    ] of CryTUI::InputEvent)
    # 16 is control, 4 is shift.
    parser.feed("\e[<20;4;9M").should eq([
      CryTUI::MouseEvent.new(
        CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 3, 8,
        CryTUI::KeyModifiers::Shift | CryTUI::KeyModifiers::Control
      ),
    ] of CryTUI::InputEvent)
  end

  it "waits for the rest of a split mouse report instead of mis-reading it" do
    parser = CryTUI::InputParser.new

    parser.feed("\e[<0;10").should be_empty
    parser.feed(";7M").should eq([
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 9, 6),
    ] of CryTUI::InputEvent)
  end

  it "falls back to the X10 encoding when a terminal ignores the SGR request" do
    parser = CryTUI::InputParser.new
    # ESC [ M, then button, column, row, each biased by 32.
    frame = String.new(Bytes[0x1B, 0x5B, 0x4D, 32 + 0, 32 + 8, 32 + 3])

    parser.feed(frame).should eq([
      CryTUI::MouseEvent.new(CryTUI::MouseKind::Press, CryTUI::MouseButton::Left, 7, 2),
    ] of CryTUI::InputEvent)
  end

  it "keeps reading after a mouse report, rather than stalling the stream" do
    parser = CryTUI::InputParser.new

    # Before mouse parsing existed the `<` fell outside the CSI character class,
    # so these bytes matched nothing and the parser waited for a completion that
    # never came, freezing every later keystroke.
    events = parser.feed("\e[<0;3;4Mq")
    events.size.should eq(2)
    events.last.should eq(CryTUI::KeyEvent.character('q'))
  end
end
