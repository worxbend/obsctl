require "../spec_helper"

# The frames below were taken from the Rust `tui-spinner` crate this port was
# built from, by dumping both implementations over the whole matrix of widgets,
# presets, motions, spins and sizes and diffing them. They are golden values:
# if one changes, the port has drifted from the animation it is a port of.
private def frame(lines : Array(CryTUI::Line)) : String
  lines.map(&.spans.map(&.content).join).join("\n")
end

describe CryTUI::Widgets::FluxSpinner do
  it "walks the frame sequence, one step per tick" do
    CryTUI::Widgets::FluxSpinner.new(0_u64).glyph.should eq("⣾")
    CryTUI::Widgets::FluxSpinner.new(3_u64).glyph.should eq("⣟")
    CryTUI::Widgets::FluxSpinner.new(8_u64).glyph.should eq("⣾")
  end

  it "staggers each cell by the phase step, making the sequence a wave" do
    frame(CryTUI::Widgets::FluxSpinner.new(3_u64, width: 6).lines).should eq("⣟⡿⢿⣽⣻⣾")
    frame(CryTUI::Widgets::FluxSpinner.new(0_u64, width: 4, phase_step: 0).lines).should eq("⣾⣾⣾⣾")
  end

  it "runs the sequence backwards when the spin is counter-clockwise" do
    spinner = CryTUI::Widgets::FluxSpinner.new(
      3_u64,
      width: 4,
      spin: CryTUI::Widgets::Spin::CounterClockwise,
      frames: CryTUI::Widgets::FluxFrames::MOON
    )
    frame(spinner.lines).should eq("◑◓◐◒")
  end

  it "holds a frame for as many ticks as it is told to" do
    CryTUI::Widgets::FluxSpinner.new(3_u64, ticks_per_step: 4_u64).glyph.should eq("⣾")
    CryTUI::Widgets::FluxSpinner.new(4_u64, ticks_per_step: 4_u64).glyph.should eq("⣷")
  end

  it "carries every preset the crate ships, and looks them up by name" do
    CryTUI::Widgets::FluxFrames::ALL.size.should eq(21)
    CryTUI::Widgets::FluxFrames.by_name("CIRCLE-FILL").should eq(CryTUI::Widgets::FluxFrames::CIRCLE_FILL)
    CryTUI::Widgets::FluxFrames.by_name("nope").should be_nil
    CryTUI::Widgets::FluxFrames::ALL.each_value(&.should_not(be_empty))
  end

  it "takes a frame sequence of its own, so an ASCII surface can still spin" do
    CryTUI::Widgets::FluxSpinner.new(1_u64, frames: %w[| / - \\]).glyph.should eq("/")
    CryTUI::Widgets::FluxSpinner.new(1_u64, frames: [] of String).lines.should be_empty
  end
end

describe CryTUI::Widgets::LinearSpinner do
  it "scrolls a lit window along the row and wraps it round the end" do
    spinner = CryTUI::Widgets::LinearSpinner.new(3_u64, total_slots: 8, lit_slots: 3)
    frame(spinner.lines).should eq("·●●●····")
  end

  it "runs the window the other way when the flow is backwards" do
    forwards = CryTUI::Widgets::LinearSpinner.new(3_u64, total_slots: 8, lit_slots: 3, ticks_per_step: 1_u64)
    backwards = CryTUI::Widgets::LinearSpinner.new(
      3_u64, total_slots: 8, lit_slots: 3, ticks_per_step: 1_u64, flow: CryTUI::Widgets::Flow::Backwards
    )
    frame(forwards.lines).should eq("···●●●··")
    frame(backwards.lines).should eq("····●●●·")
  end

  it "bounces a single slot between the ends when it runs vertically" do
    positions = (0..8).map do |tick|
      CryTUI::Widgets::LinearSpinner.new(
        tick.to_u64, total_slots: 5, ticks_per_step: 1_u64, direction: CryTUI::Direction::Vertical
      ).bounce_index
    end
    positions.should eq([0, 1, 2, 3, 4, 3, 2, 1, 0])
  end

  it "pins its slots to the bottom of a taller area" do
    spinner = CryTUI::Widgets::LinearSpinner.new(
      0_u64, total_slots: 2, direction: CryTUI::Direction::Vertical
    )
    frame(spinner.vertical_lines(4)).should eq("\n\n●\n·")
  end

  it "points its arrows along whichever axis it is drawn on" do
    CryTUI::Widgets::LinearStyle::Arrow.symbols(CryTUI::Direction::Horizontal).should eq({"▶", "▷"})
    CryTUI::Widgets::LinearStyle::Arrow.symbols(CryTUI::Direction::Vertical).should eq({"▼", "▽"})
  end
end

describe CryTUI::Widgets::SquareSpinner do
  it "walks an arc round the ring" do
    frame(CryTUI::Widgets::SquareSpinner.new(0_u64).lines).should eq("⣤⣤⡄⠀\n⠿⠰⠆⠀\n⠀⠀⠀⠀")
    frame(CryTUI::Widgets::SquareSpinner.new(7_u64).lines).should eq("⠀⠀⣤⣤\n⠀⠰⠆⣿\n⠀⠀⠀⠀")
  end

  it "mirrors the frame to spin the other way" do
    clockwise = CryTUI::Widgets::SquareSpinner.new(9_u64, size: 3)
    counter = CryTUI::Widgets::SquareSpinner.new(9_u64, size: 3, spin: CryTUI::Widgets::Spin::CounterClockwise)
    mirrored = clockwise.lines.first.spans.map(&.content)
    mirrored.reverse!
    counter.lines.first.spans.map(&.content).should eq(mirrored)
  end

  it "reports the cells it needs before anything is drawn" do
    CryTUI::Widgets::SquareSpinner.new(0_u64).char_size.should eq({4, 3})
    CryTUI::Widgets::SquareSpinner.new(0_u64, size: 4).char_size.should eq({9, 5})
  end

  it "costs the same at any age, because the walk folds into one revolution" do
    # A dashboard left open for a day must not pay a day of steps per frame.
    late = frame(CryTUI::Widgets::SquareSpinner.new(1_000_000_u64, size: 3).lines)
    late.should eq("⣿⡿⠿⠿⠀⠀⠀\n⣿⡇⢰⣶⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⠀\n⠀⠀⠀⠀⠀⠀⠀")
  end
end

describe CryTUI::Widgets::CircleSpinner do
  it "rotates an arc round a dimmed ring" do
    frame(CryTUI::Widgets::CircleSpinner.new(0_u64).lines).should eq("⡰⠊⠉⠲⡀\n⠁⡀⠀⣠⠃\n⠀⠈⠉⠀⠀")
    frame(CryTUI::Widgets::CircleSpinner.new(5_u64).lines).should eq("⡰⠈⠉⠲⡀\n⢣⡀⠀⣠⠃\n⠀⠈⠉⠀⠀")
  end

  it "folds a long-running tick back into one revolution" do
    spinner = CryTUI::Widgets::CircleSpinner.new(999_999_u64, radius: 6, spin: CryTUI::Widgets::Spin::CounterClockwise)
    frame(spinner.lines).should eq("⢀⠔⠉⠉⠑⢄⠀\n⡇⠀⠀⠀⠀⠀⡀\n⠑⢄⠀⠀⢀⠔⠁\n⠀⠀⠉⠉⠁⠀⠀")
  end

  it "collapses to a single dot at radius zero rather than dividing by it" do
    CryTUI::Widgets::CircleSpinner.perimeter(0).should eq([CryTUI::Widgets::RingCoord.new(0, 0)])
  end
end

describe CryTUI::Widgets::BarSpinner do
  it "bounces a fading glow along the bar" do
    frame(CryTUI::Widgets::BarSpinner.new(4_u64).lines(24)).should eq("⣀⣀⣀⣀⠉⠛⠿⣿⣿⠿⠛⠉⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀")
  end

  it "draws every motion the crate defines" do
    loop_bar = CryTUI::Widgets::BarSpinner.new(
      4_u64, bar_style: CryTUI::Widgets::BarStyle::Star, motion: CryTUI::Widgets::BarMotion::Loop
    )
    squeeze = CryTUI::Widgets::BarSpinner.new(6_u64, motion: CryTUI::Widgets::BarMotion::Squeeze)
    radiate = CryTUI::Widgets::BarSpinner.new(
      6_u64, motion: CryTUI::Widgets::BarMotion::Radiate, bar_style: CryTUI::Widgets::BarStyle::Block
    )

    frame(loop_bar.lines(24)).should eq("☆☆☆☆★★★★★★★★☆☆☆☆☆☆☆☆☆☆☆☆")
    frame(squeeze.lines(24)).should eq("⣀⣀⣀⣀⣀⣀⠉⠛⠿⣿⣿⠿⠛⠉⣿⠿⠛⠉⣀⣀⣀⣀⣀⣀")
    frame(radiate.lines(24)).should eq("██████░░░░░░░░░░░░██████")
  end

  it "runs down a column when it is turned vertical" do
    spinner = CryTUI::Widgets::BarSpinner.new(3_u64, orientation: CryTUI::Direction::Vertical, thickness: 2)
    frame(spinner.lines(2, 8)).should eq("⣀⣀\n⣀⣀\n⣀⣀\n⣿⣿\n⣿⣿\n⣿⣿\n⣀⣀\n⣀⣀")
  end

  it "folds a long-running tick back into one period" do
    frame(CryTUI::Widgets::BarSpinner.new(10_000_000_u64).lines(20)).should eq("⣀⣀⣀⠉⠛⠿⣿⠿⠛⠉⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀")
  end

  it "carries every symbol style, and only braille uses dot bytes" do
    CryTUI::Widgets::BarStyle.values.size.should eq(16)
    CryTUI::Widgets::BarStyle::Braille.chars.should be_nil
    CryTUI::Widgets::BarStyle.values.reject(&.braille?).each(&.chars.should_not(be_nil))
  end

  it "draws the unlit track from whichever byte the track style names" do
    CryTUI::Widgets::BarTrack::RAIL.byte.should eq(0xC0_u8)
    CryTUI::Widgets::BarTrack::FULL.byte.should eq(0xFF_u8)
    CryTUI::Widgets::BarTrack::EMPTY.byte.should eq(0x00_u8)
    CryTUI::Widgets::BarTrack.custom(0x18_u8).byte.should eq(0x18_u8)
  end
end

describe "spinner rendering" do
  it "draws into a buffer through an optional block" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 12, 4))
    block = CryTUI::Widgets::Block.new(title: "go")
    CryTUI::Widgets::FluxSpinner.new(0_u64, width: 3, block: block).render(buffer.area, buffer)

    buffer.lines[0].should contain("go")
    buffer.lines[1].should contain("⣾⣷⣯")
  end

  it "leaves an area with no room in it alone" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 8, 2))
    empty = CryTUI::Rect.new(0, 0, 0, 0)

    CryTUI::Widgets::FluxSpinner.new(0_u64).render(empty, buffer)
    CryTUI::Widgets::BarSpinner.new(0_u64).render(empty, buffer)
    CryTUI::Widgets::CircleSpinner.new(0_u64).render(empty, buffer)
    CryTUI::Widgets::SquareSpinner.new(0_u64).render(empty, buffer)
    CryTUI::Widgets::LinearSpinner.new(0_u64).render(empty, buffer)

    buffer.lines.should eq(["        ", "        "])
  end

  it "clips a spinner larger than the area it is given" do
    buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, 3, 1))
    CryTUI::Widgets::SquareSpinner.new(0_u64, size: 5).render(buffer.area, buffer)

    buffer.lines.size.should eq(1)
    buffer.lines[0].size.should eq(3)
  end
end
