require "../spec_helper"
require "../../src/crytui"

describe "CryTUI terminal lifecycle" do
  it "clears and fully redraws after shrinking and expanding" do
    output = IO::Memory.new
    backend = CryTUI::AnsiBackend.new(output, 12, 4, alternate_screen: false)
    terminal = CryTUI::Terminal.new(backend)

    terminal.start
    terminal.draw do |frame|
      frame.buffer.set_string(0, 0, "original")
      frame.buffer.set_string(0, 3, "bottom-row")
    end
    before_shrink = output.bytesize

    backend.resize(5, 2)
    terminal.draw(&.buffer.set_string(0, 0, "small"))
    shrink_output = output.to_s.byte_slice(before_shrink, output.bytesize - before_shrink)
    shrink_output.should start_with("\e[0m\e[2J\e[H")
    # A resize must repaint blank cells too; otherwise an old border can remain
    # one column beside the new edge when the terminal ignores/defers CSI 2J.
    shrink_output.should contain("\e[2;5H ")
    terminal.area.should eq(CryTUI::Rect.new(0, 0, 5, 2))

    before_expand = output.bytesize
    backend.resize(16, 6)
    terminal.draw(&.buffer.set_string(0, 5, "expanded"))
    expand_output = output.to_s.byte_slice(before_expand, output.bytesize - before_expand)
    expand_output.should start_with("\e[0m\e[2J\e[H")
    terminal.area.should eq(CryTUI::Rect.new(0, 0, 16, 6))
  ensure
    terminal.try(&.stop)
  end

  it "disables wrapping during the session and restores it on exit" do
    output = IO::Memory.new
    backend = CryTUI::AnsiBackend.new(output, 10, 3, alternate_screen: false)
    terminal = CryTUI::Terminal.new(backend)

    terminal.run { }

    output.to_s.should contain("\e[?7l")
    output.to_s.should contain("\e[?7h")
  end

  it "restores the exact PTY mode after an exception" do
    helper = File.expand_path("../fixtures/crytui/raw_restore_helper.cr", __DIR__)
    command = "crystal run #{Process.quote(helper)}"
    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run("script", ["--quiet", "--return", "--command", command, "/dev/null"], output: output, error: error)

    status.success?.should be_true, "PTY probe failed: #{error}\n#{output}"
    output.to_s.should contain("CRYTUI_RAW_RESTORED")
    output.to_s.should contain("CRYTUI_RESIZE_DETECTED")
    output.to_s.should contain("CRYTUI_REPEAT_RESIZE_REDRAW")
  end
end

describe CryTUI::AnsiBackend do
  it "enables mouse reporting on entry and releases it on the way out" do
    output = IO::Memory.new
    backend = CryTUI::AnsiBackend.new(output, 10, 3, alternate_screen: true)

    CryTUI::Terminal.new(backend).run { }
    rendered = output.to_s

    rendered.should contain(CryTUI::AnsiBackend::MOUSE_ON)
    rendered.should contain(CryTUI::AnsiBackend::MOUSE_OFF)
    # Tracking has to stop before the alternate screen is given back, or a
    # terminal that outlives the process keeps spraying reports at the shell.
    rendered.index!(CryTUI::AnsiBackend::MOUSE_OFF).should be < rendered.index!("\e[?1049l")
  end

  it "leaves mouse reporting alone when it is switched off" do
    output = IO::Memory.new
    backend = CryTUI::AnsiBackend.new(output, 10, 3, alternate_screen: false, mouse: false)

    CryTUI::Terminal.new(backend).run { }

    output.to_s.should_not contain("1006")
  end
end
