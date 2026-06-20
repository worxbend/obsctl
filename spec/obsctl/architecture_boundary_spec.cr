require "../spec_helper"

private ROOT                      = File.expand_path("../..", __DIR__)
private EMBEDDED_TUI_OBS_ADAPTERS = [
  "src/obsctl/tui/obs_session_client.cr",
]
private SERVER_OBS_OWNERS = [
  "src/obsctl/server/obs_supervisor.cr",
]
private NORMAL_CLIENT_LAYER_GLOBS = [
  "src/obsctl/cli/**/*.cr",
  "src/obsctl/tui/**/*.cr",
  "src/obsctl/ipc/**/*.cr",
  "src/obsctl/domain/**/*.cr",
  "src/obsctl/support/**/*.cr",
]
private DIRECT_OBS_CLIENT_PATTERNS = [
  {name: "OBS client require", regex: /require\s+"(?:\.\.\/)+obs\/client"/},
  {name: "OBS connection require", regex: /require\s+"(?:\.\.\/)+obs\/connection"/},
  {name: "OBS client instantiation", regex: /\b(?:Obsctl::)?OBS::Client\.new\b/},
  {name: "OBS connection reference", regex: /\b(?:Obsctl::)?OBS::Connection\b/},
]

private def src_files(glob : String) : Array(String)
  Dir.glob(File.join(ROOT, glob)).sort
end

private def src_files(globs : Array(String)) : Array(String)
  globs.flat_map { |glob| src_files(glob) }.uniq.sort
end

private def src_path(path : String) : String
  File.join(ROOT, path)
end

private def relative_path(path : String) : String
  path.sub("#{ROOT}/", "")
end

private def direct_obs_client_usages(paths : Array(String), allowlist = [] of String) : Array(String)
  offenders = [] of String

  paths.each do |path|
    relative = relative_path(path)
    next if allowlist.includes?(relative)

    File.read(path).lines.each_with_index(1) do |line, line_number|
      DIRECT_OBS_CLIENT_PATTERNS.each do |pattern|
        if line.matches?(pattern[:regex])
          offenders << "#{relative}:#{line_number}: #{pattern[:name]}"
        end
      end
    end
  end

  offenders
end

private def pattern_usages(paths : Array(String), regex : Regex, label : String) : Array(String)
  offenders = [] of String

  paths.each do |path|
    relative = relative_path(path)
    File.read(path).lines.each_with_index(1) do |line, line_number|
      offenders << "#{relative}:#{line_number}: #{label}" if line.matches?(regex)
    end
  end

  offenders
end

private def usage_files(usages : Array(String)) : Array(String)
  usages.map { |usage| usage.split(':', 2).first }.uniq.sort
end

describe "daemon-first architecture boundary" do
  it "keeps normal CLI, TUI, IPC, domain, and support layers off the OBS websocket client implementation" do
    normal_client_files = src_files(NORMAL_CLIENT_LAYER_GLOBS)

    direct_obs_client_usages(normal_client_files, EMBEDDED_TUI_OBS_ADAPTERS).should eq([] of String)
    usage_files(direct_obs_client_usages(normal_client_files)).should eq(EMBEDDED_TUI_OBS_ADAPTERS)
  end

  it "keeps the normal TUI client path off the OBS websocket client implementation" do
    tui_files = src_files("src/obsctl/tui/**/*.cr")

    direct_obs_client_usages(tui_files, EMBEDDED_TUI_OBS_ADAPTERS).should eq([] of String)
    usage_files(direct_obs_client_usages(tui_files)).should eq(EMBEDDED_TUI_OBS_ADAPTERS)

    normal_entrypoints = [
      src_path("src/obsctl.cr"),
      src_path("src/obsctl/cli/main.cr"),
      src_path("src/obsctl/tui/app.cr"),
      src_path("src/obsctl/tui/session.cr"),
      src_path("src/obsctl/tui/session_client.cr"),
    ]
    pattern_usages(normal_entrypoints, /obs_session_client|ObsSessionClient/, "embedded OBS adapter reference").should eq([] of String)
  end

  it "keeps server-owned OBS client construction inside the supervisor" do
    server_files = src_files("src/obsctl/server/**/*.cr")

    direct_obs_client_usages(server_files, SERVER_OBS_OWNERS).should eq([] of String)
    usage_files(direct_obs_client_usages(server_files)).should eq(SERVER_OBS_OWNERS)
  end

  it "keeps command executor as the IPC-command-to-OBS-action boundary" do
    server_files = src_files("src/obsctl/server/**/*.cr")
    command_executor_path = "src/obsctl/server/command_executor.cr"
    executor = File.read(src_path(command_executor_path))

    executor.should contain("def execute(request : IPC::Request) : IPC::Response")
    executor.should contain("private def execute_command(command : IPC::CommandPayload)")
    executor.should contain("@supervisor.with_client")
    direct_obs_client_usages([src_path(command_executor_path)]).should eq([] of String)

    payload_usages = pattern_usages(server_files, /\bIPC::CommandPayload\b/, "IPC command payload handling")
    usage_files(payload_usages).should eq([command_executor_path])

    supervisor_calls = pattern_usages(server_files, /@supervisor\.with_client\b/, "OBS action execution")
    usage_files(supervisor_calls).should eq([command_executor_path])
  end
end
