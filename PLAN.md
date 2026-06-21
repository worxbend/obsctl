# obsctl Improvement Plan

This plan reflects a fresh senior review of the 2026-06-21 iteration 7
diagnostic-observability slice. The iteration added focused
`Server::BestEffortLogBroadcast` unit coverage and exposed aggregate dropped
secondary reconnect diagnostic log-topic deliveries as
`dropped_reconnect_diagnostic_logs` in daemon status and combined status.

## Current Assessment

`obsctl` has a mature local daemon architecture: one server owns the OBS
WebSocket session, thin CLI/TUI clients use Unix socket IPC, public CLI/IPC
contracts are fixture-backed, reconnect behavior has focused primitive and
integration specs, and reconnect diagnostic fanout is bounded and lossy.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Completed or correct in the reviewed reconnect and diagnostic work:

- `ObsSupervisor#reconnect` preserves the generation-safe accept-then-emit
  boundary: lifecycle acceptance, reconnect request registration, active-client
  detachment, and authoritative reconnect state mutation are decided under
  `@lifecycle_lock`, while publication side effects happen after the lock is
  released.
- Detached OBS clients are closed before state/log fanout can block, and cleanup
  is protected with `ensure`.
- Accepted reconnect state/log publication exceptions are diagnostic-only after
  lifecycle acceptance and detached-client cleanup.
- Reconnect diagnostics write sanitized diagnostics to the runtime logger first.
- Secondary reconnect diagnostic log-topic fanout is routed through
  `Server::BestEffortLogBroadcast`, which caps outstanding async deliveries and
  drops new secondary diagnostics when capacity is exhausted.
- Secondary reconnect diagnostics bypass `Server#broadcast_log`, avoiding
  duplicate runtime-log entries when the primary runtime diagnostic has already
  been written.
- Focused `BestEffortLogBroadcast` unit specs now cover capacity validation,
  outstanding-count cleanup, exception containment, drop accounting while full,
  and recovery after blocked workers drain.
- Aggregate secondary reconnect diagnostic drops are exposed as
  `dropped_reconnect_diagnostic_logs` in `server-status` and in the `server`
  object of combined `status`, with CLI docs and golden fixtures updated.
- Server reconnect specs use `SpecSupport::TcpGate` instead of
  unavailable-then-bind `unused_tcp_port` windows.
- Fake OBS exposes accepted/closed WebSocket connection identifiers, letting
  specs prove the exact detached connection closed.
- `OBS::Client#wait_for_close` is the supervisor's primary established
  disconnect signal, with a short defensive fallback timeout.
- Strict Rust compatibility remains manual/scheduled until `obsctl-rs` owns a
  matching contract fixture root.

Reviewer findings from the latest pass:

- No blocking correctness regression was found in the new diagnostic drop-count
  behavior.
- The new helper unit specs directly cover the previously indirect
  `BestEffortLogBroadcast` behavior.
- The public drop counter is useful operator telemetry for slow or blocked
  reconnect diagnostic subscribers, and it does not change reconnect command
  liveness.
- The CLI human formatter currently renders a missing
  `dropped_reconnect_diagnostic_logs` field as `0`. That preserves older-payload
  formatting, but it conflates "daemon did not report this field" with "zero
  drops". This should be resolved before treating mixed-version status output as
  a polished contract.
- The drop counter is process-local runtime telemetry and resets on daemon
  restart; docs should say this explicitly.
- The counter is stored as `UInt64` and serialized through JSON. Practically it
  will not overflow, but the public JSON contract would be cleaner with an
  explicitly JSON-safe non-negative integer policy or saturation behavior.
- Ordinary state/log/event broadcasts still use synchronous
  `ClientRegistry#broadcast`, so broader slow-subscriber isolation is still
  future work.

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
   - `reconnect_obs` returns success once the live supervisor accepts the request
     and detached-client cleanup has happened.

4. Bound reconnect diagnostic log-topic fanout.
   - `Server::BestEffortLogBroadcast` limits outstanding secondary diagnostic
     deliveries.
   - Excess secondary diagnostics are dropped.
   - Runtime logger delivery remains the durable primary sink.
   - Secondary log-topic delivery avoids the runtime logger path to prevent
     duplicate persisted diagnostics.

5. Expose aggregate diagnostic drops.
   - `dropped_reconnect_diagnostic_logs` is present in daemon status and
     combined status.
   - Command-executor, CLI, server, and golden contract specs cover the field.
   - Focused helper specs cover the bounded fanout accounting that feeds it.

## Completed P1: Reconnect Determinism Slice

1. Retire server reconnect unavailable-then-bind port races.
   - `SpecSupport::TcpGate` reserves a port without listening, causing
     connection attempts to fail immediately while preserving ownership.
   - Server reconnect specs open fake OBS through the gate instead of using
     `unused_tcp_port` windows.

2. Add connection-specific fake OBS close probes.
   - Fake OBS assigns accepted WebSocket ids.
   - Specs can assert that the specific detached connection closed, not merely
     that some close event happened.

3. Make established disconnect waiting event-driven first.
   - `OBS::Client#wait_for_close` exposes sanitized terminal close/error
     notification.
   - `ObsSupervisor#wait_for_disconnect` waits on that notification before the
     fallback timeout and keeps event draining.
   - Close-notification specs cover disconnect, explicit close, malformed
     frames, response parser failures, pending requests, and secret redaction.

## P0: Finish Strict Compatibility Fixture Ownership

1. Add or coordinate the Rust-side shared fixture root.
   - Create one recognized root in `obsctl-rs`:
     `spec/fixtures/contracts/`, `tests/fixtures/contracts/`, or
     `fixtures/contracts/`.
   - Populate matching `cli/human/`, `cli/json/`, and `ipc/` fixtures.
   - Include `dropped_reconnect_diagnostic_logs` in the status fixtures or make
     a deliberate public-contract decision if Rust should expose a different
     observability shape.
   - Run `make contract-rs-compat` in a prepared dual-repo workspace and treat
     content differences as public-contract decisions.

2. Keep strict compatibility separate from the default gate until fixtures exist.
   - Default `make test` must stay deterministic in single-repo and accidental
     sibling-checkout workspaces.
   - Strict compatibility should fail loudly only in explicitly prepared
     dual-repo contexts.
   - Once the Rust fixtures exist and pass, decide whether scheduled/manual is
     enough or whether the workflow should become a required PR signal.

## P1: Status And Diagnostic Contract Polish

1. Clarify missing versus zero drop-count semantics.
   - Decide whether older daemon payloads missing
     `dropped_reconnect_diagnostic_logs` should render as `-`/unknown instead of
     `0` in human output.
   - Add a compatibility spec for the chosen behavior.
   - Keep JSON output faithful to the daemon payload unless a versioned default
     policy is explicitly chosen.

2. Document counter lifecycle precisely.
   - State that `dropped_reconnect_diagnostic_logs` is process-local runtime
     telemetry.
   - State that it resets on daemon restart.
   - State that it counts only secondary reconnect diagnostic log-topic drops,
     not ordinary log/state/event subscriber drops.

3. Make the counter's numeric contract explicit.
   - Prefer an `Int64`/JSON-safe non-negative counter or documented saturation
     behavior over exposing an unbounded `UInt64` through `JSON::Any`.
   - Add a small unit spec for the serialized field type.

4. Consider exposing current diagnostic pressure.
   - `outstanding` is useful internally but not currently public.
   - If operators need more signal, add a separate status field such as
     `reconnect_diagnostic_logs_in_flight`; avoid expanding status unless it
     answers a real operational question.

## P1: Remaining Reconnect Test Polish

1. Tighten close-notification semantics if more consumers appear.
   - Today one supervisor waiter is the only production consumer, so a single
     buffered close notification plus terminal-error fallback is adequate.
   - If command paths, diagnostics, or tests start waiting concurrently, replace
     the single notification channel with a condition-style primitive or
     per-waiter channels.
   - Add a focused spec documenting the intended single-owner or multi-waiter
     semantics before broadening use.

2. Continue replacing polling/sleep-based reconnect specs.
   - Convert remaining elapsed-time/no-event assertions to fake OBS probes where
     practical.
   - Replace the ad hoc `StateStore` subclass used as a pre-delay barrier with a
     narrower supervisor test hook if it remains useful.
   - Keep fallback sleeps only where the behavior under test is explicitly
     "nothing happened during this interval".

3. Clarify fake OBS probe naming and usage.
   - Keep `connection_attempt_count` documented as accepted WebSocket
     connections.
   - Use names like `accepted_websocket_connection_id` for accepted sockets and
     avoid implying failed TCP attempts are counted.
   - Prefer connection-id assertions for any future overlapping reconnect specs.

## P1: Broader Slow-Subscriber Policy

1. Decide whether `BestEffortLogBroadcast` should become a broader primitive.
   - Today it is intentionally scoped to reconnect diagnostics.
   - Ordinary state/log/event broadcasts still use synchronous
     `ClientRegistry#broadcast`.
   - A future registry-level slow-subscriber policy should drop, evict, or bound
     slow sessions rather than blocking command paths indefinitely.

2. Preserve runtime logging as the durable sink.
   - Do not route best-effort secondary diagnostics back through
     `Server#broadcast_log` if the primary logger has already written them.
   - Keep secret redaction before every public or persisted diagnostic surface.

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

1. Coordinate the Rust-side `obsctl-rs` contract fixture root and run
   `make contract-rs-compat` in a prepared dual-repo workspace.
2. Polish the new status telemetry contract: missing-versus-zero human output,
   counter reset/scope docs, and JSON-safe numeric semantics.
3. Continue reconnect spec polish by replacing remaining sleep/no-event
   assertions with deterministic probes where practical.
4. Decide whether `OBS::Client#wait_for_close` should remain a single-owner
   supervisor primitive or become a multi-waiter close notification primitive.
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
