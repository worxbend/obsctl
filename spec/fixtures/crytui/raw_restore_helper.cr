require "io/console"
require "termios"
require "../../../src/crytui"

private def terminal_mode
  mode = uninitialized LibC::Termios
  raise "tcgetattr failed" unless LibC.tcgetattr(STDIN.fd, pointerof(mode)) == 0
  mode
end

before = terminal_mode
backend = CryTUI::AnsiBackend.for_terminal(STDOUT, STDIN, alternate_screen: false)
terminal = CryTUI::Terminal.new(backend)
raise "terminal size was not discovered" if terminal.area.empty?

resize_status = Process.run("stty", ["rows", "33", "cols", "101"], input: STDIN, output: STDOUT, error: STDERR)
raise "stty resize failed" unless resize_status.success?
raise "terminal resize was not detected" unless terminal.refresh_size
raise "wrong resized area: #{terminal.area}" unless terminal.area == CryTUI::Rect.new(0, 0, 101, 33)

begin
  terminal.run(STDIN) do
    terminal.draw(&.buffer.set_string(0, 0, "wide"))

    shrink_status = Process.run("stty", ["rows", "14", "cols", "47"], input: STDIN, output: STDOUT, error: STDERR)
    raise "stty shrink failed" unless shrink_status.success?
    terminal.draw(&.buffer.set_string(0, 0, "small"))
    raise "draw did not discover shrink: #{terminal.area}" unless terminal.area == CryTUI::Rect.new(0, 0, 47, 14)

    expand_status = Process.run("stty", ["rows", "29", "cols", "88"], input: STDIN, output: STDOUT, error: STDERR)
    raise "stty expansion failed" unless expand_status.success?
    terminal.draw(&.buffer.set_string(0, 0, "expanded"))
    raise "draw did not discover expansion: #{terminal.area}" unless terminal.area == CryTUI::Rect.new(0, 0, 88, 29)
    raise "expected probe exception"
  end
rescue exception
  raise exception unless exception.message == "expected probe exception"
end

after = terminal_mode
raise "terminal mode was not restored" unless before == after
puts "CRYTUI_RAW_RESTORED"
puts "CRYTUI_RESIZE_DETECTED"
puts "CRYTUI_REPEAT_RESIZE_REDRAW"
