# obsctl Improvement Plan

This plan reflects the fresh reviewer pass on the June 20, 2026 iteration 7
supervisor lifecycle work. The default Crystal gate is green, supervisor runs
are now generation-scoped, and reconnect wake tokens no longer leak across
supervisor generations or active-client reconnects.

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

- `ObsSupervisor` run loops now carry the lifecycle generation that created
  them. Stale fibers exit when a newer generation starts and cannot reclaim the
  OBS client slot.
- `stop` invalidates the active generation, clears the current wake signal, and
  closes the active OBS client outside the lifecycle lock.
- `start` creates a fresh per-generation reconnect wake signal and still ignores
  accidental double starts while alive.
- Reconnect wake tokens are no longer buffered on one supervisor-wide channel.
  A wake emitted while closing an active client is dropped instead of being
  consumed by a later unrelated retry delay.
- Focused supervisor coverage now proves stop followed by immediate start keeps
  OBS ownership with the newest generation.
- Focused supervisor coverage now proves a stale reconnect wake from an active
  close does not skip the next scheduled retry delay.
- `TODO.md` and `MEMORY.md` were refreshed for generation-scoped supervisor
  ownership.

Validation observed during review:

- Focused touched specs passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec spec/obsctl/server/obs_supervisor_spec.cr`
  with 7 examples.
- Default validation passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  with 246 examples.
- Full build/format/lint were not rerun in this reviewer pass after plan/log
  edits; the implementation log reports the focused supervisor spec only for
  iteration 7. The full standard gate remains required before checkpointing a
  code change.

Reviewer findings:

- No blocking default-gate regression was found.
- The P0 stop-then-start ownership bug from iteration 6 is fixed in the normal
  paths reviewed: lifecycle checks, client claiming, and stop cleanup are now
  generation-aware.
- The stale buffered wake-token bug is fixed by replacing the shared buffered
  channel with a per-generation unbuffered signal object.
- The new unbuffered signal intentionally drops wakes when no retry delay is
  currently waiting. That prevents stale tokens, but it creates a narrow
  operator-visible race: a fresh `reconnect_obs` request that lands after a
  failed connection attempt but just before the supervisor enters
  `wait_for_reconnect_delay` can be lost and the loop can still sleep for the
  full backoff.
- `reconnect` still marks state as `OBS reconnect requested` even when there is
  no active client and the wake signal is dropped. That is acceptable while the
  supervisor is already sleeping, but ambiguous in the pre-delay race above.
- `wait_for_disconnect` still polls every 250 ms. The generation fix makes it
  correct, but stop/reconnect responsiveness and tests still depend on polling.
- Reconnect specs still use `unused_tcp_port` for unavailable-then-bind
  scenarios, so the remaining flake surface is smaller but not eliminated.
- The strict compatibility workflow remains manual/scheduled and still needs
  compatible Rust-side fixtures before it can become a required signal.

## P0: Close Remaining Reconnect Wake Race

1. Preserve fresh operator reconnect requests without reintroducing stale tokens.
   - Replace the lossy unbuffered wake-only signal with a per-generation request
     epoch, monotonic counter, or explicit wake reason.
   - A reconnect request made while no delay is currently waiting should either
     be consumed by the next delay boundary immediately or return a clear
     "attempt already in progress" style success state.
   - A reconnect wake created by active-client close must still not survive into
     a later unrelated retry delay.

2. Add adversarial coverage for reconnect timing boundaries.
   - Force the supervisor through: failed attempt observed, reconnect request
     accepted before delay wait starts, OBS becomes available, and Identify is
     sent promptly instead of after the full delay.
   - Keep the existing stale-token negative test and add assertions that the two
     wake cases are distinguishable.
   - Prefer deterministic test hooks over timing windows where practical.

3. Clarify public reconnect semantics.
   - Decide whether `reconnect_obs` success means "a new request was recorded",
     "the active delay was woken", or "an attempt is already in progress or will
     run promptly".
   - Align `CommandExecutor`, server status, logs, README, command docs, and
     protocol docs to that exact meaning.

## P0: Finish Strict Compatibility Signal Ownership

1. Add or coordinate the Rust-side shared fixture root.
   - Create one recognized root in `obsctl-rs`:
     `spec/fixtures/contracts/`, `tests/fixtures/contracts/`, or
     `fixtures/contracts/`.
   - Populate matching `cli/human/`, `cli/json/`, and `ipc/` fixtures.
   - Run `make contract-rs-compat` in a prepared dual-repo workspace and treat
     content differences as real public-contract decisions.

2. Keep strict compatibility separate from the default gate until fixtures
   exist.
   - Default `make test` must stay deterministic in single-repo and accidental
     sibling-checkout workspaces.
   - Strict compatibility should fail loudly only in explicitly prepared
     dual-repo contexts.
   - Once the Rust fixtures exist and pass, decide whether scheduled/manual is
     enough or whether the workflow should become a required PR signal.

## P1: Reduce Reconnect Test Flake Surface

1. Remove `unused_tcp_port` races from reconnect specs.
   - Add a deterministic unavailable-then-bind helper that owns port selection
     and delayed fake-server startup.
   - Prefer helpers that reserve the intended port until the exact test moment
     when OBS should become reachable.

2. Continue replacing polling/sleep-based reconnect specs.
   - Convert remaining reconnect tests from generic polling helpers to fake OBS
     probes for Identify received, close observed, request received, and
     no-attempt windows.
   - Add a specific probe or hook for "connection attempt failed and delay is
     about to start" so wake-race tests do not depend on sleeps.
   - Keep polling only for state-store changes that are inherently asynchronous
     across IPC.

3. Make disconnect detection more event-driven.
   - Replace or supplement the `wait_for_disconnect` polling sleep with a close
     notification from `OBS::Client` when practical.
   - Keep a fallback timeout path for defensive cleanup.

## P1: Main CI And Validation Polish

1. Add main CI for the Crystal gates.
   - `crystal tool format --check`
   - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec`
   - `crystal build src/obsctl.cr -o bin/obsctl`
   - `make lint` or Ameba when dependencies are installed

2. Make lint meaningful in CI.
   - Decide whether Ameba should be a development dependency.
   - If yes, install it in CI and fail on lint issues.
   - If no, keep the skip explicit and document that lint is currently a local
     optional gate.

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
   - reconnect command accepted/rejected
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

1. Make reconnect requests durable across the pre-delay boundary without
   reintroducing stale active-close wake tokens.
2. Add deterministic unavailable-then-bind and pre-delay supervisor hooks to
   remove the remaining reconnect timing races from specs.
3. Add or coordinate the Rust-side `obsctl-rs` contract fixtures, then run
   `make contract-rs-compat` in a prepared dual-repo workspace.

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
