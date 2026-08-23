require "../spec_helper"
require "../../src/crytui"

describe CryTUI::Color do
  it "computes WCAG contrast ratios" do
    black = CryTUI::Color.rgb(0, 0, 0)
    white = CryTUI::Color.rgb(255, 255, 255)

    CryTUI::Color.contrast_ratio(black, white).not_nil!.should be_close(21.0, 0.01)
    CryTUI::Color.contrast_ratio(white, white).not_nil!.should be_close(1.0, 0.01)
  end

  it "has no contrast ratio for colours the terminal resolves" do
    # An indexed colour is whatever the user's palette says it is, so its
    # luminance is not knowable here.
    CryTUI::Color.contrast_ratio(CryTUI::Color::RED, CryTUI::Color.rgb(0, 0, 0)).should be_nil
  end
end

describe CryTUI::ForegroundGuard do
  it "replaces only the colours that cannot be read on the background" do
    # Roughly material-ocean's selection bar, whose `muted` grey lands at about
    # 1.05:1 against it — invisible — while its foreground reads fine.
    bar = CryTUI::Color.rgb(0x30, 0x54, 0x5A)
    muted = CryTUI::Color.rgb(0x46, 0x4B, 0x5D)
    foreground = CryTUI::Color.rgb(0xA6, 0xAC, 0xCD)
    guard = CryTUI::ForegroundGuard.new(foreground, bar, 3.0)

    guard.insufficient?(muted).should be_true
    guard.insufficient?(foreground).should be_false
  end

  it "leaves a span with no colour of its own alone" do
    # Nil already inherits the row's colour; there is nothing to rescue.
    guard = CryTUI::ForegroundGuard.new(CryTUI::Color.rgb(255, 255, 255), CryTUI::Color.rgb(0, 0, 0), 3.0)

    guard.insufficient?(nil).should be_false
  end
end

describe CryTUI::Widgets::List do
  it "rescues an illegible span on the selected row and keeps a legible one" do
    bar = CryTUI::Color.rgb(0x30, 0x54, 0x5A)
    muted = CryTUI::Color.rgb(0x46, 0x4B, 0x5D)
    foreground = CryTUI::Color.rgb(0xEC, 0xE8, 0xE1)
    warning = CryTUI::Color.rgb(0xF0, 0xE0, 0x50)

    item = CryTUI::Widgets::ListItem.new([
      CryTUI::Line.new([
        CryTUI::Span.new("ab", CryTUI::Style.new(foreground: muted)),
        CryTUI::Span.new("cd", CryTUI::Style.new(foreground: warning)),
      ]),
    ])
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 8, 1))
    CryTUI::Widgets::List.new(
      [item],
      highlight_style: CryTUI::Style.new(foreground: foreground, background: bar)
    ).render(buffer.area, buffer, CryTUI::Widgets::ListState.new(selected: 0))

    # The muted span was unreadable on the bar, so it takes the highlight
    # foreground; the amber one reads fine and keeps its meaning.
    buffer[0, 0].style.foreground.should eq(foreground)
    buffer[2, 0].style.foreground.should eq(warning)
  end

  it "leaves unselected rows untouched" do
    muted = CryTUI::Color.rgb(0x46, 0x4B, 0x5D)
    item = CryTUI::Widgets::ListItem.new([
      CryTUI::Line.new([CryTUI::Span.new("ab", CryTUI::Style.new(foreground: muted))]),
    ])
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 8, 1))
    CryTUI::Widgets::List.new(
      [item],
      highlight_style: CryTUI::Style.new(
        foreground: CryTUI::Color.rgb(0xEC, 0xE8, 0xE1),
        background: CryTUI::Color.rgb(0x30, 0x54, 0x5A)
      )
    ).render(buffer.area, buffer, CryTUI::Widgets::ListState.new(selected: nil))

    buffer[0, 0].style.foreground.should eq(muted)
  end
end
