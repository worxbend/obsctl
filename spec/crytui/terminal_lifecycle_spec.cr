require "../spec_helper"

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
