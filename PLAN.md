# obsctl Improvement Plan

This plan reflects a fresh senior review of the 2026-06-21 reconnect
diagnostic-liveness slice. Accepted reconnects now complete after lifecycle
acceptance and detached-client cleanup even when publication-failure diagnostics
cannot be delivered to log-topic subscribers. The next highest-value work is to
bound the remaining detached fanout resource risk, then continue reconnect flake
cleanup and Rust fixture ownership.

## Current Assessment

`obsctl` has a mature local daemon architecture: one server owns the OBS
WebSocket session, thin CLI/TUI clients use Unix socket IPC, public CLI/IPC
contracts are fixture-backed, reconnect behavior has focused primitive specs,
and the default Crystal gate is green at 267 examples.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Completed or correct in the reviewed slice:

- `ObsSupervisor#reconnect` still preserves the accept-then-emit boundary:
  lifecycle/generation acceptance, reconnect request registration, active-client
  detachment, and authoritative reconnect state mutation are decided under
  `@lifecycle_lock`.
- Detached OBS clients are closed immediately after the lifecycle lock is
  released and before state/log fanout can block; cleanup remains protected with
  `ensure`.
- Accepted reconnect state/log publication exceptions are diagnostic-only after
  lifecycle acceptance and detached-client cleanup.
- Reconnect publication diagnostics now write sanitized diagnostics to the
  runtime logger first, when one is configured.
- Log-topic delivery of reconnect diagnostics is secondary and detached, so a
  blocked `@log_broadcast` callback no longer blocks the accepted reconnect
  command.
- New supervisor specs cover blocked diagnostic log fanout after both state
  publication failure and log publication failure.
- New command-level coverage proves sanitized fallback diagnostics reach the
  runtime logger when diagnostic log-topic delivery itself raises.
- The deterministic reconnect-vs-stop spec still proves the stop-wins
  interleaving where reconnect observes a live generation, pauses, `stop`
  completes, reconnect resumes, and stale public reconnect state remains
  unobservable.
- Strict Rust compatibility remains manual/scheduled until `obsctl-rs` owns a
  matching contract fixture root.

Reviewer findings from the latest pass:

- No blocking correctness regression was found in the targeted reconnect
  diagnostic-liveness behavior.
- The implementation satisfies the previous P0 liveness decision: accepted
  reconnects no longer synchronously depend on diagnostic log-topic fanout.
- Diagnostics remain redacted before runtime logging and log-topic broadcast.
- The current detached diagnostic fanout is implemented as an untracked spawned
  fiber. This protects command liveness, but a permanently blocked subscriber
  can leave a fiber parked indefinitely. Repeated publication failures could
  accumulate parked fibers.
- Runtime logger delivery is synchronous and file-backed. That is acceptable as
  the durable local sink today because the logger rescues internally, but a
  future high-volume diagnostic path should avoid doing repeated per-event file
  opens on hot paths.
- `Server#broadcast_log` still writes diagnostics to the runtime logger after
  registry broadcast. Because reconnect diagnostics now write the logger before
  detached fanout, successfully delivered diagnostics may be duplicated in the
  runtime log.
- Close-observed specs still do not identify the specific OBS connection that
  closed, which limits future overlapping reconnect assertions.
- Remaining reconnect flake sources are unchanged: some reconnect specs still
  depend on unavailable-then-bind port windows and `wait_for_disconnect` still
  polls every 250 ms.

## P0: Bound Best-Effort Diagnostic Fanout

1. Replace ad hoc detached diagnostic broadcast with a bounded helper.
   - Add a small `best_effort_log_broadcast` or server-side async fanout helper
     with clear ownership and bounded resource behavior.
   - Avoid spawning unlimited permanently blocked fibers for repeated
     reconnect publication failures.
   - Preserve the public contract: diagnostic log-topic delivery must never
     block accepted reconnect completion.

2. Define slow-subscriber behavior for best-effort diagnostics.
   - Prefer dropping or evicting slow log-topic subscribers over accumulating
     blocked diagnostic workers.
   - Keep runtime logger delivery as the primary durable diagnostic sink.
   - Add specs proving repeated blocked diagnostic fanout does not create
     unbounded outstanding work or block later reconnect commands.

3. Avoid duplicate runtime-log diagnostics.
   - Ensure reconnect diagnostics are written once through the runtime logger
     primary path, even if secondary log-topic broadcast succeeds.
   - Preserve normal `logs` topic delivery for TUI clients.

## P0: Finish Strict Compatibility Fixture Ownership

1. Add or coordinate the Rust-side shared fixture root.
   - Create one recognized root in `obsctl-rs`:
     `spec/fixtures/contracts/`, `tests/fixtures/contracts/`, or
     `fixtures/contracts/`.
   - Populate matching `cli/human/`, `cli/json/`, and `ipc/` fixtures.
   - Run `make contract-rs-compat` in a prepared dual-repo workspace and treat
     content differences as public-contract decisions.

2. Keep strict compatibility separate from the default gate until fixtures exist.
   - Default `make test` must stay deterministic in single-repo and accidental
     sibling-checkout workspaces.
   - Strict compatibility should fail loudly only in explicitly prepared
     dual-repo contexts.
   - Once the Rust fixtures exist and pass, decide whether scheduled/manual is
     enough or whether the workflow should become a required PR signal.

## P1: Reduce Reconnect Test Flake Surface

1. Retire unavailable-then-bind port races.
   - Replace remaining `unused_tcp_port` style windows with the deterministic
     port-reservation helper already introduced for reconnect specs.
   - Ensure helper/probe names distinguish accepted WebSocket connections from
     failed TCP attempts.

2. Continue replacing polling/sleep-based reconnect specs.
   - Convert remaining reconnect tests to fake OBS probes for Identify received,
     close observed, request received, and no-attempt windows.
   - Add connection identifiers to fake OBS close probes so specs can assert the
     exact detached client closed when reconnect and retry attempts overlap.
   - Replace the ad hoc `StateStore` subclass used as a pre-delay barrier with a
     narrower supervisor test hook if it remains useful.

3. Make disconnect detection more event-driven.
   - Replace or supplement the 250 ms `wait_for_disconnect` polling loop with an
     OBS client close/error notification.
   - Keep a defensive timeout or polling fallback for cleanup.

## P1: Main CI And Validation Polish

1. Add main CI for the Crystal gates.
   - `crystal tool format --check`
   - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec`
   - `crystal build src/obsctl.cr -o bin/obsctl`
   - `make lint` or Ameba when dependencies are installed

2. Make lint meaningful in CI.
   - Decide whether Ameba should be a development dependency.
   - If yes, install it in CI and fail on lint issues.
   - If no, keep the skip explicit and document that lint is currently optional.

## P1: Config And Security

1. Reject unknown nested config fields.
   - Extend validation to `server`, `connection`, `reconnect`, `ui`,
     `audio.inputs`, `scenes`, and `keymap`.

2. Add `obsctl doctor`.
   - Validate config, password env var, OBS reachability, socket directory
     permissions, daemon state, systemd user service state, and stale aliases.

3. Add config migration/explain commands.
   - `obsctl config migrate`
   - `obsctl config explain`
   - `obsctl config diff-from-obs`

4. Keep secrets out of all public surfaces.
   - Logs, IPC errors, JSON output, TUI panels, specs, and fixtures.

## P1: Logging And Observability

1. Make logs a first-class IPC stream.
   - Keep the `logs` topic stable.
   - Use structured payloads with `level`, `message`, `target/code`, and
     `timestamp`.
   - Redact before broadcast.

2. Add lifecycle log events.
   - socket bound, reconnect scheduled, reconnect attempt started/failed/succeeded,
     reconnect accepted/rejected, config reloaded, and command failed.

3. Improve TUI log rendering.
   - Truncate long messages cleanly.
   - Preserve recent warning/error visibility.
   - Avoid letting logs dominate narrow terminal layouts.

## P2: Product Features

Add breadth only after the daemon/IPC/reconnect contract remains stable.

1. Recording controls: `record start|stop|pause|resume|status`.
2. Streaming controls: `stream start|stop|status`.
3. Replay buffer and virtual camera: `replay start|save`,
   `virtualcam start|stop|status`.
4. Scene/source operations: transitions, source visibility, filters,
   screenshots, profiles, and scene collections.
5. Script-friendly event stream: `obsctl watch`, `obsctl watch --json`,
   newline-delimited JSON, topic filters.
6. Macros: YAML-defined sequences for scene/audio/wait/record/stream actions.

## P2: TUI Upgrade

1. Treat the TUI as an operator dashboard.
   - daemon state, OBS state, active scene, scene groups, audio state,
     recording/streaming timers, recent events, and recent logs.

2. Improve command palette ergonomics.
   - command history, fuzzy completion, alias completion from current snapshot,
     and validation before submit.

3. Add recovery UX.
   - daemon unavailable screen, retry, service install/start commands, and
     optional explicit embedded mode if retained.

## P3: Open Source Polish

1. Add release packaging.
   - GitHub release artifacts, Homebrew tap, AUR, Nix flake, and Debian/RPM
     packages if demand appears.

2. Improve docs.
   - architecture document, IPC protocol spec, CLI contract spec, security
     model, contributor guide, streamer recipes, and demo media.

3. Decide the two-project strategy.
   - If Rust is flagship, make Crystal intentionally experimental or legacy.
   - If both stay alive, share a public protocol spec and compatibility suite.
   - Avoid solving the same product and protocol questions twice.

## Suggested Next Pull Requests

1. Bound reconnect diagnostic log-topic fanout so blocked subscribers cannot
   accumulate parked detached fibers or duplicate runtime-log entries.
2. Replace remaining reconnect unavailable-then-bind port windows with the
   deterministic reservation helper.
3. Add connection-specific fake OBS close probes and keep removing
   sleep/poll-based reconnect assertions.
4. Add or coordinate the Rust-side `obsctl-rs` contract fixtures, then run
   `make contract-rs-compat` in a prepared dual-repo workspace.
5. Add main Crystal CI and decide whether Ameba should become an installed dev
   dependency.

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
