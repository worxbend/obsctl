require "file_utils"
require "../../spec_helper"

private ROOT    = File.expand_path("../../..", __DIR__)
private CRYSTAL = ENV["CRYSTAL"]? || "crystal"

private record CompileResult, status : Process::Status, stdout : String, stderr : String

private def compile_snippet(source : String) : CompileResult
  dir = File.join(ROOT, ".tmp-embedded-adapter-require-#{Process.pid}-#{Random.rand(1_000_000)}")
  path = File.join(dir, "check.cr")
  stdout = IO::Memory.new
  stderr = IO::Memory.new

  Dir.mkdir_p(dir)
  File.write(path, source)

  status = Process.run(CRYSTAL, ["build", "--no-codegen", path], output: stdout, error: stderr)
  CompileResult.new(status, stdout.to_s, stderr.to_s)
ensure
  FileUtils.rm_rf(dir) if dir
end

describe "embedded TUI OBS adapter require contract" do
  it "loads the direct OBS adapter only through the explicit obs_session_client require" do
    result = compile_snippet(<<-CRYSTAL)
      require "../src/obsctl/tui/obs_session_client"

      config = Obsctl::Config::Config.default
      client = Obsctl::TUI::ObsSessionClient.new(config)
      client.is_a?(Obsctl::TUI::SessionClient) || raise "adapter did not implement session client"
      CRYSTAL

    result.status.success?.should be_true, result.stderr
  end

  it "does not implicitly load the direct OBS adapter through session_client" do
    result = compile_snippet(<<-CRYSTAL)
      require "../src/obsctl/tui/session_client"

      Obsctl::TUI::ObsSessionClient
      CRYSTAL

    result.status.success?.should be_false
    result.stderr.should contain("undefined constant Obsctl::TUI::ObsSessionClient")
  end
end
