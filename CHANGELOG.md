# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`shard.yml` and `src/obsctl/version.cr` carry the version currently in
development; the `Unreleased` section below becomes that version at tag time.

## [Unreleased]

## [0.4.0] - 2026-08-01

### Added

- A **Stats** pane in the TUI, beside the logs, that appears while the stream is
  live. It reports active FPS with a rolling sparkline, average frame render
  time as a share of the frame budget, and the frames OBS missed to rendering
  lag and skipped to encoding lag, each with its drop ratio. Values are colored
  by severity — under 1% dropped is nominal, 5% or more is critical — and the
  panel summarizes the worst of them as one verdict. It reads the `GetStats`
  sample the daemon already polls, so it adds no OBS traffic, and it gives up
  its column when the terminal is too narrow for both panes.

### Fixed

- A single input with no audio track — an image, colour, or silent browser
  source — no longer stops the daemon from working at all. `GetInputList`
  returns every input, and OBS answers a mute or volume read on a non-audio one
  with "The specified input does not support audio.", which failed the entire
  state snapshot. The supervisor read that as a lost connection and reconnected
  forever, so the daemon never became usable. Inputs whose audio state OBS will
  not report are now left out of the audio matrix instead.
- A failed OBS request is no longer logged as `obs_disconnected`. It logs as
  `obs_request_failed`, so a refused request is not mistaken for a network
  fault.
- Streaming or recording started outside obsctl — from the OBS UI or another
  obs-websocket client — is now reflected in daemon state, so the dashboard
  shows `LIVE` and the CLI reports it. The daemon's Identify mask omitted the
  `Outputs` category, and obs-websocket only delivers an event to clients
  subscribed to its category, so `StreamStateChanged` and `RecordStateChanged`
  never arrived and their handlers never ran. State only looked correct when
  obsctl itself issued the toggle, or after a daemon restart.
- Profile and scene-collection changes made outside obsctl now reach the
  dashboard too. The same missing-category bug applied to `Config` events.
- Output state is also reconciled from the periodic telemetry poll, so it
  converges within one poll interval even if an event is never delivered.

## [0.3.0] - 2026-07-26

### Added

- `obsctl completions bash|zsh|fish` prints a shell completion script generated
  from the command registry, so it always matches the binary. Scene, profile,
  collection, and audio-input names complete from the running daemon via
  `obsctl completions candidates <kind>`, which is bounded by a short timeout
  and stays silent when the daemon is unreachable.
- `--color auto|always|never`. Human output is decorated only when stdout is a
  terminal; `NO_COLOR` and `TERM=dumb` disable it as well.
- `-q`/`--quiet` suppresses human output and leaves the exit code as the only
  signal. `--json` output is unaffected.
- `--timeout SECONDS` bounds a single daemon round trip, reporting
  `REQUEST_TIMEOUT` and exit `3` when it elapses.
- `--help` now lists every command with its usage and summary, not just the
  global options.
- `obsctl version`, `obsctl --version`, and `-V` report the binary version.
  Supports `--json`, which emits the standard envelope with a `version` field.
- A CI workflow that runs formatting, lint, build, and specs on every push to
  `master` and every pull request, against both the declared Crystal floor and
  the latest release.
- `.ameba.yml`, making the lint configuration explicit. Every disabled rule and
  per-path exclusion carries a comment explaining why.
- `make check` runs all four gates; `make format-check` runs the formatter in
  verification mode.
- `LICENSE` (MIT), `CONTRIBUTING.md`, `SECURITY.md`, and this changelog.
- Release builds for `linux-arm64` alongside `linux-amd64`, plus a published
  `SHA256SUMS.txt`.
- `obsctl doctor` reports config, credential, socket, daemon, OBS, and service
  diagnostics with a remedy for every problem it finds. Exits `1` when any
  check fails; warnings alone do not fail it. Supports `--json`.
- Explicit recording controls: `obsctl record start|stop|toggle|pause|resume|status`.
  Bare `obsctl rec` still toggles. `record status` returns structured
  `active`, `paused`, `timecode`, `duration_ms`, and `bytes` fields alongside
  the message, and `stop` reports the written file path.
- `obsctl watch` streams daemon events as newline-delimited JSON, one object
  per line, flushed as written. `--topics` selects a subset of `state`,
  `events`, and `logs`.
- `obsctl config explain` shows every effective setting with the source that
  supplied it; `obsctl config diff` shows only departures from the defaults;
  `obsctl config migrate [--dry-run]` rewrites the file in the current schema,
  dropping unrecognized top-level sections and backing up the original.
- A contract manifest audit that runs in the normal suite, failing when a
  fixture exists on disk without a manifest entry or vice versa, and when an
  entry's category, behavior, or telemetry flag disagrees with reality.

### Changed

- The `claude` and `codex` themes are renamed to `ember` and `slate`. `ember`
  remains the default. Both old ids still resolve to the same palette, so an
  existing `config.yml` keeps working and needs no edit.
- CI lints on the Crystal floor leg only, and the `latest` leg installs with
  `--production`. Ameba analyses source rather than the compiler, so running it
  twice over the same tree added nothing, while its released version (1.6.4)
  does not build on current Crystal — `shards install` failed in postinstall,
  which skipped the build and spec steps and reported a red build for code that
  was fine. The `latest` leg now answers what it exists to answer: does obsctl
  compile and pass its specs on the newest compiler.
- The command set is declared once, in `Domain::CommandRegistry`. The parser,
  the `--json` allowlist, palette completion, `--help`, the palette help text,
  and the generated shell completions all read that declaration. It previously
  lived in six hand-maintained lists that had already drifted apart, and a spec
  now asserts the surfaces agree.
- Commands carry their own IPC name and payload arguments, replacing the two
  type-to-name tables in `CLI::ClientCommands` and the two in `TUI::Dispatcher`.
  The dashboard's two deliberate divergences are declared as such.
- Argument-count errors name the command and show its usage
  (`wrong argument count for scene; usage: scene <scene>`) instead of a bare
  `missing argument`.
- `-h`/`--help` writes to the injected output stream and returns, instead of
  writing to the process stdout and calling `exit 0` from inside the option
  parser.
- `OptionsParser` derives its argv splitting from the same flag declarations it
  builds the parser from, replacing a hand-maintained list of which flags take
  a value.
- Config value types are declared with a single `config_value` field list that
  produces the getters, the YAML mapping, and the initializer. The hand-written
  YAML parsing helpers are gone; the canonical writer is kept deliberately,
  because it defines the on-disk format `obsctl config migrate` converges to.
  Emitted YAML is byte-identical.
- Release binaries are now statically linked against musl, so they no longer
  depend on the host's glibc version.
- `make lint` builds `bin/ameba` from the pinned checkout when it is absent,
  and fails loudly if the checkout itself is missing. It previously printed a
  notice and exited successfully, so the lint gate silently passed on any
  machine without ameba installed.
- Version is `0.3.0`: `shard.yml` still read `0.1.0` when `v0.2.0` was tagged,
  and master has since reintroduced the full TUI.
- `Metrics/CyclomaticComplexity` is enforced at 25 rather than disabled. The
  dispatchers that dominated it were split into named groups and lookup
  tables: `TUI::Input#handle` (was 45), `TUI::Dispatcher#handle` (36),
  `CLI::Main.run` (36), `CommandExecutor#execute_command` (26),
  `Domain::CommandParser#parse` (24), and both `payload_for` mappings (23).
  `CLI::Main.run` is now only an error boundary that delegates to `dispatch`.

### Fixed

- Scene and audio-input names containing a quote or a backslash reach the
  daemon intact. The CLI used to rebuild its already-split arguments into a
  quoted line and re-parse it, which rejected `obsctl scene 'quo"te'` outright
  and silently rewrote `a\ b` to `a b`. Arguments now go straight from argv to
  the parser. Control characters, tabs included, are still refused — that is
  deliberate — but a tab now reports `target must not contain control
  characters` rather than the misleading `wrong argument count`.
- `--json` works for every spelling of a JSON-capable command. `set-scene`,
  `set-profile`, and `set-collection` parsed fine but were rejected by the
  hand-maintained allowlist.
- `obsctl watch | head` exits `0` instead of printing
  `write (...): Broken pipe` and exiting `1`. A closed reader is a normal end
  of stream for a streaming command.
- Human output no longer emits ANSI escapes when stdout is not a terminal, so
  `obsctl status > file` and grep-based scripting see plain text.
- `SIGTERM` and `SIGINT` shut the daemon down in order. Neither was trapped, so
  the default disposition killed the process before `Server#stop` could close
  the OBS WebSocket, log the stop, or remove the socket file — the exact path
  `systemctl --user stop obsctl` takes.
- Socket directories obsctl creates are `0700`. The `/tmp/obsctl-$UID/`
  fallback sits in a world-writable parent and was created at the ambient
  umask. A pre-existing directory owned by another user, writable by others,
  and without the sticky bit is now refused rather than used.
- The three flat contract fixtures at the root of `spec/fixtures/contracts/`
  are canonicalized into `cli/json/` and `ipc/`. Two were exact duplicates of
  existing canonical fixtures; the third, `cli_scene_error.json`, was the only
  unique one and is now `cli/json/scene_error.json` with a manifest entry. The
  fixture root and its manifest agree in both directions again.
- Specs no longer write to the real STDOUT. `Main.run` defaults to the process
  streams, and eleven call sites were taking that default, printing daemon and
  command output between the progress dots.
- The JSON CLI path no longer raises `NilAssertionError` when a daemon returns
  a not-ok response with no error payload; it now raises the protocol error
  that the human-output path already raised.

### Removed

- Six unreachable files: `src/obsctl/support/{result,time,json_helpers}.cr`,
  `src/obsctl/runtime/{event_loop,scheduler}.cr`, and the self-described legacy
  `src/obsctl/cli/command_router.cr`. All but the router were never required by
  anything; the router was required but never instantiated.
- `spec/obsctl/contract/` is merged into `spec/obsctl/contracts/`. Two
  directories a letter apart, with no matching directory under `src/`.
- `PLAN.md` and `scripts/agent-loop.sh`. The script had been dead since the
  Markdown control files it required were deleted, and `PLAN.md` pointed at a
  task queue under the gitignored `.agent-loop/`, so its roadmap was not
  visible to contributors.

## [0.2.0] - 2026-06-28

### Changed

- Made the user service resilient: fixed unit ordering, removed restart limits,
  and allowed startup to survive a missing config file.
- Improved CLI output styling.

### Removed

- TUI mode. (Reintroduced, rewritten on CryTUI, in the unreleased work above.)

## [0.1.0] - 2026-06-24

Initial release: the local daemon, the automation CLI, and config handling.

[Unreleased]: https://github.com/worxbend/obsctl/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/worxbend/obsctl/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/worxbend/obsctl/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/worxbend/obsctl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/worxbend/obsctl/releases/tag/v0.1.0
