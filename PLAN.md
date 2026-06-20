# obsctl Improvement Plan

This plan reflects the fresh reviewer pass on the June 20, 2026 iteration 4
contract-reliability work. The default Crystal validation gate is reliable
again in this workspace, reconnect telemetry is more honest, and strict
`obsctl-rs` fixture compatibility is now explicit. The next risk is not broad
feature absence; it is making the stabilized contracts operationally trustworthy
in CI and in edge-case reconnect flows.

## Current Assessment

`obsctl` is a serious local OBS controller with a daemon, Unix socket IPC, thin
CLI/TUI clients, service installation, config dump/validation, a fake OBS
server, golden public-contract fixtures, optional dual-repo compatibility
checks, and broad Crystal specs.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Completed in the latest implementation iteration:

- Default `make test` no longer runs strict `../obsctl-rs` compatibility checks.
  In this workspace, where `../obsctl-rs` exists without recognized contract
  fixtures, `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test` passed with
  224 examples.
- `make contract-rs-compat` now sets
  `OBSCTL_STRICT_OBSCTL_RS_COMPAT=1` and fails clearly for missing sibling
  repositories, missing fixture roots, missing counterpart fixtures, and content
  differences.
- The GitHub compatibility workflow now checks out both repositories before
  running the strict compatibility target.
- Server status and combined status now expose `last_connection_failed_at` in
  addition to `last_connected_at`, `last_disconnected_at`, and
  `last_reconnect_attempt_at`.
- `last_disconnected_at` is updated only for an actual connected-to-disconnected
  transition; initial connection failures update `last_connection_failed_at`
  instead.
- Explicit `obsctl reconnect` keeps public state at
  `"OBS reconnect requested"` until the next connection success or failure,
  rather than exposing the intentional clean close as the latest operator state.
- README, command docs, protocol docs, contract fixtures, and `TODO.md` were
  refreshed for the strict/default compatibility split and reconnect telemetry
  contract.

Reviewer findings:

- No blocking default validation regression was found. The default test gate now
  passes in the accidental-sibling workspace that previously failed.
- Strict compatibility intentionally fails in this workspace because the local
  `../obsctl-rs` checkout has no recognized contract fixture root. The error is
  clear and useful, but the new always-on GitHub workflow will also fail until
  the real `obsctl-rs` repository contains compatible fixtures or the workflow
  is made manual/conditional.
- `ObsSupervisor#reconnect` still only detaches/closes the active client. If the
  supervisor fiber has already exited after an OBS startup failure with
  `reconnect.enabled: false`, `reconnect_obs` can return success and publish
  `"OBS reconnect requested"` without any fiber left to attempt a connection.
- `last_connection_failed_at` is useful, but the contract should be sharpened:
  decide whether a later successful connection should clear historical startup
  failure state or whether the field intentionally means "most recent failed
  connection attempt".
- Reconnect specs are improved but still rely on polling and sleeps in helper
  loops. This is acceptable for now, but deterministic fake-server probes would
  reduce flake risk around connection attempts and state publication.
- Some CLI unit specs still use status payloads without
  `last_connection_failed_at`; the formatter tolerates this and golden fixtures
  cover the public shape, but adding explicit assertions would make local unit
  coverage less dependent on golden tests.

## P0: Make Strict Compatibility CI Actionable

1. Decide how the `obsctl-rs` compatibility workflow should run before it becomes
   a required signal.
   - If strict compatibility is required on every push/PR, add compatible
     `cli/` and `ipc/` contract fixtures to `obsctl-rs` first.
   - If the Rust repository is not ready, change the workflow to
     `workflow_dispatch` or a clearly named non-required job until fixtures
     exist.
   - Consider making the sibling repository configurable with a workflow input or
     repository variable instead of hardcoding `w0rxbend/obsctl-rs`.

2. Strengthen strict compatibility diagnostics.
   - Print the selected fixture root before comparison.
   - Include a short "how to create the missing fixture root" note in the strict
     failure.
   - Add a small README section in `docs/protocol.md` or a new contract doc that
     states the shared fixture layout expected by both repositories.

## P0: Make Explicit Reconnect Semantics Complete

1. Fix `reconnect_obs` when no active client exists.
   - If the supervisor loop is alive, the command can keep acting as a wake/drop
     request.
   - If the supervisor loop has exited because reconnect is disabled, either
     start a one-shot connection attempt or return a clear public error instead
     of a success response.
   - Add integration coverage for `reconnect.enabled: false`, OBS unavailable at
     startup, then `obsctl reconnect` after OBS becomes available.

2. Decide and document the exact meaning of `last_connection_failed_at`.
   - Option A: preserve it as the most recent failed connection attempt until a
     newer failure occurs.
   - Option B: clear it on a successful connection so the field only describes
     the current disconnected episode.
   - Align README, command docs, protocol docs, fixtures, and server specs with
     the chosen meaning.

3. Tighten status contract unit coverage.
   - Add explicit CLI unit assertions for `last_connection_failed_at` in human
     and JSON status paths, not only golden fixtures.
   - Add focused `StateStore` unit specs for startup failure, passive
     disconnect, failed reconnect after prior success, explicit reconnect, and
     successful reconnect.

## P1: Test Determinism And Main CI

1. Continue replacing polling/sleep-based reconnect specs.
   - Extend fake OBS probes for connection attempt started, client detached,
     close observed, and reconnect attempt completed.
   - Prefer channels over fixed `sleep 50.milliseconds` loops where practical.

2. Add main CI for the Crystal gates.
   - `crystal tool format --check`
   - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec`
   - `crystal build src/obsctl.cr -o bin/obsctl`
   - `make lint` or Ameba when dependencies are installed

3. Keep strict cross-repo compatibility separate from the default gate.
   - The default suite must remain deterministic in single-repo workspaces.
   - Strict compatibility should fail loudly only in explicitly prepared
     dual-repo contexts.

## P1: Config And Security

1. Reject unknown nested config fields.
   - Extend validation to `server`, `connection`, `reconnect`, `ui`,
     `audio.inputs`, `scenes`, and `keymap`.

2. Add `obsctl doctor`.
   - Validate config.
   - Check password env var.
   - Check OBS websocket reachability.
   - Check socket directory permissions.
   - Check whether daemon is running.
   - Check systemd user service state.
   - Report stale aliases from OBS discovery.

3. Add config migration/explain commands.
   - `obsctl config migrate`
   - `obsctl config explain`
   - `obsctl config diff-from-obs`

4. Keep secrets out of all public surfaces.
   - Logs
   - IPC error payloads
   - JSON output
   - TUI panels
   - Specs and fixtures

## P1: Logging And Observability

1. Make logs a first-class IPC stream.
   - Keep the `logs` topic stable.
   - Use structured payloads with `level`, `message`, `target/code`, and
     `timestamp`.
   - Redact before broadcast.

2. Add lifecycle log events.
   - socket bound
   - reconnect scheduled
   - reconnect attempt started/failed/succeeded
   - config reloaded
   - command failed

3. Improve TUI log rendering.
   - Truncate long messages cleanly.
   - Preserve recent warning/error visibility.
   - Avoid allowing logs to dominate narrow terminal layouts.

## P2: Product Features

Add breadth only after the daemon/IPC contract remains stable.

1. Recording controls:
   `record start|stop|pause|resume|status`.
2. Streaming controls:
   `stream start|stop|status`.
3. Replay buffer and virtual camera:
   `replay start|save`, `virtualcam start|stop|status`.
4. Scene and source operations:
   transitions, source visibility, filters, screenshots, profiles, and scene
   collections.
5. Script-friendly event stream:
   `obsctl watch`, `obsctl watch --json`, newline-delimited JSON, topic
   filters.
6. Macros:
   YAML-defined sequences for scene/audio/wait/record/stream actions.

## P2: TUI Upgrade

1. Treat the TUI as an operator dashboard.
   - daemon state
   - OBS state
   - active scene
   - scene groups
   - audio state
   - recording/streaming timers
   - recent events
   - recent logs

2. Improve command palette ergonomics.
   - command history
   - fuzzy command completion
   - alias completion from current snapshot
   - validation before submit

3. Add recovery UX.
   - daemon unavailable screen
   - retry
   - show service install/start commands
   - optional explicit embedded mode if retained

## P3: Open Source Polish

1. Add release packaging.
   - GitHub release artifacts
   - Homebrew tap
   - AUR package
   - Nix flake
   - Debian/RPM packages if demand appears

2. Improve docs.
   - architecture document
   - IPC protocol spec
   - CLI contract spec
   - security model
   - contributor guide
   - streamer recipes
   - demo GIF or short terminal recording

3. Decide the two-project strategy.
   - If Rust is flagship, make Crystal intentionally experimental or legacy.
   - If both stay alive, share a public protocol spec and compatibility suite.
   - Avoid solving the same product and protocol questions twice without a
     deliberate reason.

## Suggested Next Pull Requests

1. Make `reconnect_obs` either start a real one-shot connection attempt after a
   stopped supervisor or return a truthful public error.
2. Add or coordinate `obsctl-rs` contract fixtures, then decide whether the
   strict compatibility workflow should be required on every push/PR.
3. Add focused `StateStore` and CLI status unit specs for the final reconnect
   timestamp semantics.

## Build Gates

For every Crystal change:

```sh
make format
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build
make lint
```

Strict cross-repo compatibility should run separately in a prepared dual-repo
workspace:

```sh
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make contract-rs-compat
```
