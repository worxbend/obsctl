require "../spec_helper"

private ROOT              = File.expand_path("../..", __DIR__)
private SERVER_OBS_OWNERS = [
  "src/obsctl/server/obs_supervisor.cr",
]
private NORMAL_CLIENT_LAYER_GLOBS = [
  "src/obsctl/cli/**/*.cr",
  "src/obsctl/ipc/**/*.cr",
  "src/obsctl/domain/**/*.cr",
  "src/obsctl/tui/**/*.cr",
]
private DIRECT_OBS_CLIENT_PATTERNS = [
  {name: "OBS client require", regex: /require\s+"(?:\.\.\/)+obs\/client"/},
  {name: "OBS connection require", regex: /require\s+"(?:\.\.\/)+obs\/connection"/},
  {name: "OBS client instantiation", regex: /\b(?:Obsctl::)?OBS::Client\.new\b/},
  {name: "OBS connection reference", regex: /\b(?:Obsctl::)?OBS::Connection\b/},
  # `Transport` opens the websocket itself and hands out `request`/`events`, so
  # reaching for it is the same breach as reaching for `Client` -- one level
  # lower down, where the four rules above do not look.
  {name: "OBS transport require", regex: /require\s+"(?:\.\.\/)+obs\/transport"/},
  {name: "OBS transport reference", regex: /\b(?:Obsctl::)?OBS::Transport\b/},
]

private INNER_LAYER_GLOBS = [
  "src/obsctl/domain/**/*.cr",
  "src/obsctl/config/**/*.cr",
  "src/obsctl/ipc/**/*.cr",
  "src/obsctl/obs/**/*.cr",
  "src/obsctl/runtime/**/*.cr",
]

private def src_files(glob : String) : Array(String)
  Dir.glob(File.join(ROOT, glob)).sort
end

private def src_files(globs : Array(String)) : Array(String)
  globs.flat_map { |glob| src_files(glob) }.uniq!.sort!
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
  usages.map(&.split(':', 2).first).uniq!.sort!
end

describe "daemon-first architecture boundary" do
  it "keeps CLI, IPC, domain, and TUI layers off the OBS websocket client implementation" do
    normal_client_files = src_files(NORMAL_CLIENT_LAYER_GLOBS)

    direct_obs_client_usages(normal_client_files).should eq([] of String)
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

  # CryTUI is a separate shard under crytui/, not a directory of obsctl. Two
  # rules keep that true rather than merely tidy, because both are easy to
  # break by accident and neither breaks the build when broken.
  it "keeps the dashboard out of the config file, so the daemon owns what is hidden" do
    # Scene profiles decide which scenes every client draws. If the dashboard
    # wrote them itself, a second dashboard and the CLI would read a file that
    # had changed under them, and the daemon's snapshot would disagree with what
    # is on screen. The dashboard asks; the daemon writes and pushes the answer.
    #
    # `ThemePersistence` is the deliberate exception: a theme changes nothing
    # any other client can observe.
    theme_owner = "src/obsctl/tui/theme_persistence.cr"
    offenders = src_files("src/obsctl/tui/**/*.cr").compact_map do |path|
      relative = relative_path(path)
      next if relative == theme_owner
      next unless File.read(path).matches?(/\bConfig::ConfigWriter\b/)

      relative
    end

    offenders.should eq([] of String)
  end

  it "keeps scene-profile visibility resolved in exactly one place" do
    # `Domain::SceneVisibility` is the single answer to "is this scene hidden".
    # Two places deciding it is how a client ends up disagreeing with the
    # daemon, so only the config layer (which builds it) and the domain module
    # itself may name the per-scene flag alongside a profile's list.
    resolvers = src_files([
      "src/obsctl/cli/**/*.cr",
      "src/obsctl/server/**/*.cr",
      "src/obsctl/tui/**/*.cr",
    ]).compact_map do |path|
      relative = relative_path(path)
      next unless File.read(path).matches?(/SceneVisibility\.resolve/)

      relative
    end

    # The executor resolves a *candidate* list to count what a profile would
    # hide; nothing else may.
    resolvers.should eq(["src/obsctl/server/command_executor.cr"])
  end

  it "keeps inner layers off the delivery and daemon layers" do
    # The rules, the config shapes, the wire protocol and the OBS adapter all
    # have to be reachable without dragging a terminal or a daemon in behind
    # them -- that is what lets them be read, tested and changed on their own.
    # Nothing enforced the direction, so `src/obsctl/domain/` requiring
    # `../tui/model` would have compiled and nothing would have said a word.
    inward = pattern_usages(
      src_files(INNER_LAYER_GLOBS),
      /require\s+"(?:\.\.\/)+(?:tui|server|cli)\/|require\s+"crytui"/,
      "require into a delivery or daemon layer"
    )

    inward.should eq([] of String)
  end

  it "keeps crytui a separate shard obsctl only consumes" do
    obsctl_files = src_files(["src/obsctl/**/*.cr", "src/obsctl.cr", "spec/obsctl/**/*.cr"])

    # Reaching into ../../crytui would still compile, and would quietly
    # compile a second copy of the library alongside the installed shard.
    relative = pattern_usages(obsctl_files, /require\s+"(?:\.\.\/)+crytui"/, "relative crytui require")
    usage_files(relative).should eq([] of String)

    # The dependency has to point one way. A `require` back into obsctl, or a
    # reference to its namespace, would make the library unbuildable on its own.
    crytui_files = src_files(["crytui/src/**/*.cr", "crytui/spec/**/*.cr"])
    crytui_files.should_not be_empty

    back_requires = pattern_usages(crytui_files, /require\s+"[^"]*obsctl/, "require back into obsctl")
    usage_files(back_requires).should eq([] of String)

    namespace = pattern_usages(crytui_files, /\bObsctl\b/, "obsctl namespace reference")
    usage_files(namespace).should eq([] of String)
  end
end
