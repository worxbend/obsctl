# obsctl Improvement Plan

This plan reflects a fresh senior review of the 2026-06-21 bounded reconnect
diagnostic fanout slice. Accepted reconnects now complete after lifecycle
acceptance and detached-client cleanup even when state/log publication fails,
diagnostic log-topic subscribers block, or secondary diagnostic delivery is at
capacity. Runtime logging remains the durable primary diagnostic sink.

## Current Assessment

`obsctl` has a mature local daemon architecture: one server owns the OBS
WebSocket session, thin CLI/TUI clients use Unix socket IPC, public CLI/IPC
contracts are fixture-backed, reconnect behavior has focused primitive specs,
and the default Crystal gate is green at 271 examples.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Completed or correct in the reviewed slice:

- `ObsSupervisor#reconnect` still preserves the generation-safe
  accept-then-emit boundary: lifecycle acceptance, reconnect request
  registration, active-client detachment, and authoritative reconnect state
  mutation are decided under `@lifecycle_lock`.
- Detached OBS clients are closed immediately after the lifecycle lock is
  released and before state/log publication can block; cleanup remains protected
  with `ensure`.
- Accepted reconnect state/log publication exceptions are diagnostic-only after
  lifecycle acceptance and detached-client cleanup.
- Reconnect publication diagnostics write sanitized diagnostics to the runtime
  logger first when one is configured.
- Secondary reconnect diagnostic log-topic fanout is now routed through
  `Server::BestEffortLogBroadcast`, which caps outstanding async deliveries and
  drops new secondary diagnostics once capacity is exhausted.
- Secondary reconnect diagnostics bypass `Server#broadcast_log`, avoiding
  duplicate runtime-log entries when the primary runtime diagnostic has already
  been written.
- New coverage proves blocked secondary diagnostic fanout does not block
  accepted reconnect completion; repeated blocked diagnostics reach the helper
  bound, drop excess work, and later accepted reconnects still succeed.
- Command-level coverage proves sanitized runtime diagnostics are written
  exactly once whether secondary diagnostic delivery succeeds, raises, or
  blocks.
- The deterministic reconnect-vs-stop spec still proves the stop-wins
  interleaving where reconnect observes a live generation, pauses, `stop`
  completes, reconnect resumes, and stale public reconnect state remains
  unobservable.
- Strict Rust compatibility remains manual/scheduled until `obsctl-rs` owns a
  matching contract fixture root.

Reviewer findings from the latest pass:

- No blocking correctness regression was found in the targeted bounded
  diagnostic fanout behavior.
- The previous unbounded detached diagnostic-fiber risk is addressed in the
  server path. Permanently blocked log-topic subscribers can consume only the
  helper's fixed capacity.
- The helper intentionally drops secondary diagnostics silently after capacity
  is exhausted. That preserves reconnect liveness, but operators currently have
  no aggregated visibility that log-topic diagnostics are being dropped.
- `BestEffortLogBroadcast` is covered through supervisor/server behavior, but
  it does not yet have a focused unit spec for capacity validation, exception
  containment, outstanding-count cleanup after failures, and recovery after
  blocked work is released.
- The bounded helper protects reconnect publication diagnostics only. Ordinary
  state/log/event broadcasts still use synchronous `ClientRegistry#broadcast`;
  slow IPC subscribers can still block non-diagnostic fanout paths.
- Runtime logger delivery is synchronous and file-backed. That is acceptable as
  the durable local sink today because the logger rescues internally, but a
  future high-volume diagnostic path should avoid repeated per-event file opens
  on hot paths.
- Close-observed specs still do not identify the specific OBS connection that
  closed, which limits future overlapping reconnect assertions.
- Remaining reconnect flake sources are unchanged: some reconnect specs still
  depend on unavailable-then-bind port windows and `wait_for_disconnect` still
  polls every 250 ms.

## Completed P0: Reconnect Diagnostic Liveness

1. Preserve generation-safe reconnect acceptance.
   - Reconnect acceptance is lifecycle-gated and generation-scoped.
   - Public reconnect state is not published when `stop` wins the concurrent
     reconnect-vs-stop interleaving.
   - Explicit reconnect requests are durable generation-scoped epochs; transient
     active-client-close wakes do not leak into unrelated retry delays.

2. Keep detached OBS client cleanup ahead of blockable publication.
   - Active clients detached by reconnect are closed before state/log fanout.
   - Cleanup is protected by `ensure`.
   - Specs prove cleanup before blocked state fanout, blocked log fanout, and
     unexpected publication exceptions are released.

3. Make accepted reconnect publication best-effort.
   - State/log publication failures are sanitized diagnostics after acceptance,
     not public command failures.
   - `reconnect_obs` returns success once the live supervisor accepts the
     request and detached-client cleanup has happened.

4. Bound reconnect diagnostic log-topic fanout.
   - `Server::BestEffortLogBroadcast` limits outstanding secondary diagnostic
     deliveries.
   - Excess secondary diagnostics are dropped.
   - Runtime logger delivery remains the durable primary sink.
   - Secondary log-topic delivery avoids the runtime logger path to prevent
     duplicate persisted diagnostics.

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

## P1: Reconnect Flake Cleanup

1. Retire unavailable-then-bind port races.
   - Replace remaining `unused_tcp_port` windows in reconnect specs with the
     deterministic reservation helper already introduced for this area.
   - Ensure helper and probe names distinguish accepted WebSocket connections
     from failed TCP attempts.

2. Continue replacing polling/sleep-based reconnect specs.
   - Add connection identifiers to fake OBS close probes so specs can assert the
     exact detached client closed when reconnect and retry attempts overlap.
   - Convert reconnect assertions to fake OBS probes for Identify received,
     close observed, request received, and no-attempt windows.
   - Replace the ad hoc `StateStore` subclass used as a pre-delay barrier with a
     narrower supervisor test hook if it remains useful.

3. Make disconnect detection more event-driven.
   - Replace or supplement the 250 ms `wait_for_disconnect` polling loop with
     an OBS client close/error notification.
   - Keep a defensive timeout or polling fallback for cleanup.

## P1: Diagnostic Fanout Polish

1. Add focused `BestEffortLogBroadcast` unit specs.
   - Cover positive-capacity validation.
   - Cover exception containment and outstanding-count decrement after raises.
   - Cover drop accounting while at capacity.
   - Cover recovery after blocked workers are released.

2. Make secondary diagnostic drops observable without compromising liveness.
   - Add an aggregate counter or rate-limited runtime log entry for dropped
     secondary reconnect diagnostics.
   - Avoid per-drop log spam on hot failure paths.
   - Consider exposing the drop count in daemon diagnostics or a future
     `server-status` observability section.

3. Decide whether the helper should be a broader slow-subscriber primitive.
   - Today it is intentionally scoped to reconnect diagnostics.
   - Ordinary state/log/event broadcasts still use synchronous
     `ClientRegistry#broadcast`.
   - A future registry-level slow-subscriber policy should drop, evict, or bound
     slow sessions rather than blocking command paths indefinitely.

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

1. Replace remaining reconnect unavailable-then-bind port windows with the
   deterministic reservation helper and keep the full Crystal gate green.
2. Add connection-specific fake OBS close probes and remove the next batch of
   sleep/poll-based reconnect assertions.
3. Add focused `BestEffortLogBroadcast` unit specs and an aggregate drop
   observability policy.
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
