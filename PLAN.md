# obsctl Improvement Plan

This plan reflects the fresh reviewer pass on the June 20, 2026 iteration 3
status-contract and reconnect-observability work. The daemon-first CLI/IPC
contract is now closer to the intended public shape, but the default validation
gate currently fails in this workspace because the optional `../obsctl-rs`
compatibility check became too eager.

## Current Assessment

`obsctl` is a serious local OBS controller with a daemon, Unix socket IPC, thin
CLI/TUI clients, service installation, config dump/validation, a fake OBS
server, golden public-contract fixtures, and broad Crystal specs.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Completed in the latest implementation iteration:

- `obsctl status` now sends the IPC `status` command and returns the combined
  public payload with `server` and `obs` objects.
- `obsctl obs-status` remains OBS-only, and `obsctl server-status` remains
  daemon-only.
- Human and JSON golden fixtures, IPC request fixtures, README, command docs,
  protocol docs, `TODO.md`, and `IMPLEMENTATION_CHECK_PLAN.md` were refreshed
  for the settled status contract.
- Low-level OBS protocol errors now record a terminal client error so the
  supervisor can expose malformed-frame and response-parser causes instead of
  reducing everything to a generic websocket close.
- Server status now includes explicit `reconnecting`,
  `last_connected_at`, `last_disconnected_at`, and
  `last_reconnect_attempt_at` fields.
- The optional `obsctl-rs` fixture helper now compares fixture sets in both
  directions and can fail clearly when a sibling repo exists without a
  recognized fixture root.

Reviewer findings:

- Blocking: `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test` fails in
  this workspace because `../obsctl-rs` exists but has no recognized contract
  fixture root. The implementation passed only with
  `OBSCTL_SKIP_OBSCTL_RS_COMPAT=1`, so the advertised default Crystal gate is
  no longer reliable.
- The new GitHub workflow for `obsctl-rs` compatibility checks only looks for
  `../obsctl-rs` after a normal single-repo checkout. In ordinary GitHub
  Actions it will skip forever, so it does not provide real dual-repo CI
  coverage yet.
- Reconnect telemetry is useful but not fully honest: `mark_disconnected`
  stamps `last_disconnected_at` for every failed connection attempt, including
  startup failures where OBS was never connected. That field should represent a
  transition from connected to disconnected, or the public contract should be
  renamed/split.
- Explicit reconnect semantics are slightly muddled: `reconnect` marks
  `"OBS reconnect requested"` and then the close path overwrites public state
  with `"OBS WebSocket closed cleanly"`. Decide which message should be the
  operator-facing lifecycle state.
- Protocol-error messages are secret-free and preserve category, but they are
  intentionally coarse. If operators need more detail, add sanitized internal
  debug logs without expanding public IPC/state error text.

## P0: Restore Reliable Validation

1. Make `make test` deterministic in normal single-repo development.
   - Keep optional cross-repo compatibility out of the default suite unless an
     explicit strict env var or dedicated target is set.
   - Preserve the clear failure behavior for the dedicated compatibility mode.
   - Add specs for all three modes: absent sibling, sibling without fixtures in
     default mode, and sibling without fixtures in strict mode.

2. Fix the dual-repo compatibility CI so it actually checks two repositories.
   - Either checkout `obsctl-rs` explicitly into `../obsctl-rs`, or document and
     use a reusable workflow/manual CI job that runs only in a prepared
     multi-repo workspace.
   - Run the strict compatibility target in that job.
   - Fail when fixture roots or counterparts are missing in strict mode.

## P0: Tighten Reconnect Telemetry Semantics

1. Make `last_disconnected_at` mean an actual disconnect.
   - Only update it when state transitions from connected to disconnected.
   - Do not update it on initial connection failures before any successful OBS
     session.
   - Consider adding `last_connection_failed_at` or `last_connect_error_at` if
     failed-attempt timing is valuable.
   - Add integration coverage for startup with OBS unavailable, passive
     disconnect, protocol-error disconnect, and successful reconnect.

2. Decide and test explicit reconnect lifecycle messaging.
   - Either keep `last_error` as `"OBS reconnect requested"` until the next
     connection outcome, or deliberately expose the clean close as the latest
     state.
   - Align state events, `server-status`, logs, and docs with that decision.
   - Update `ObsSupervisor#reconnect` so its code matches the documented
     "drops the active client" behavior.

3. Continue replacing fixed sleep/polling in reconnect specs.
   - Extend fake OBS probes for reconnect attempts, close acknowledgement, and
     delayed response completion.
   - Prefer deterministic channels over wall-clock polling where practical.

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

## P2: Test Infrastructure

1. Add main CI.
   - `crystal tool format --check`
   - `crystal spec`
   - `ameba` when installed
   - release build

2. Strengthen fake OBS coverage.
   - out-of-order responses
   - dropped connection
   - passive close
   - OBS request failures
   - structural scene/input events

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

1. Restore reliable default validation while preserving strict
   `obsctl-rs` fixture compatibility as an explicit target.
2. Fix the `obsctl-rs` compatibility workflow so it actually checks out and
   compares both repositories.
3. Correct reconnect timestamp semantics and explicit reconnect lifecycle
   messaging.

## Build Gates

For every Crystal change:

```sh
make format
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build
make lint
```

Strict cross-repo compatibility should run separately in a prepared dual-repo
workspace after the default gate is restored.
