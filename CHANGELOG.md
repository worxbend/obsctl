# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`shard.yml` and `src/obsctl/version.cr` carry the version currently in
development; the `Unreleased` section below becomes that version at tag time.

## [Unreleased]

### Added

- `obsctl version`, `obsctl --version`, and `-V` report the binary version.
  Supports `--json`, which emits the standard envelope with a `version` field.
- A CI workflow that runs formatting, lint, build, and specs on every push to
  `master` and every pull request, against both Crystal 1.20.2 and latest.
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

- Release binaries are now statically linked against musl, so they no longer
  depend on the host's glibc version.
- `make lint` fails with an explanatory message when `bin/ameba` is missing.
  It previously printed a notice and exited successfully, which meant the lint
  gate silently passed on any machine without ameba installed.
- Version is `0.3.0`: `shard.yml` still read `0.1.0` when `v0.2.0` was tagged,
  and master has since reintroduced the full TUI.
- `Metrics/CyclomaticComplexity` is enforced at 25 rather than disabled. The
  dispatchers that dominated it were split into named groups and lookup
  tables: `TUI::Input#handle` (was 45), `TUI::Dispatcher#handle` (36),
  `CLI::Main.run` (36), `CommandExecutor#execute_command` (26),
  `Domain::CommandParser#parse` (24), and both `payload_for` mappings (23).
  `CLI::Main.run` is now only an error boundary that delegates to `dispatch`.

### Fixed

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

[Unreleased]: https://github.com/worxbend/obsctl/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/worxbend/obsctl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/worxbend/obsctl/releases/tag/v0.1.0
