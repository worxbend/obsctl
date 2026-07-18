require "../spec_helper"

describe "CryTUI terminal lifecycle" do
  it "restores the exact PTY mode after an exception" do
    helper = File.expand_path("../fixtures/crytui/raw_restore_helper.cr", __DIR__)
    command = "crystal run #{Process.quote(helper)}"
    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run("script", ["--quiet", "--return", "--command", command, "/dev/null"], output: output, error: error)

    status.success?.should be_true, "PTY probe failed: #{error}\n#{output}"
    output.to_s.should contain("CRYTUI_RAW_RESTORED")
    output.to_s.should contain("CRYTUI_RESIZE_DETECTED")
  end
end
