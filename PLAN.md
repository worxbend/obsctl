# obsctl Improvement Plan

This plan reflects a fresh senior review of the 2026-06-21 accept-then-emit
reconnect publication slice. The implementation removes subscriber/log fanout
from `ObsSupervisor`'s lifecycle lock while preserving the generation-safe
reconnect-vs-stop proof. The next highest-risk item is resource cleanup ordering:
a blocked publication callback can still delay closing the detached OBS client.

## Current Assessment

`obsctl` has a mature local daemon architecture: one server owns the OBS
WebSocket session, thin CLI/TUI clients use Unix socket IPC, public CLI/IPC
contracts are fixture-backed, reconnect behavior has focused primitive specs,
and the default Crystal gate has recently been green at 256 examples.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Completed or correct in the reviewed slice:

- `ObsSupervisor#reconnect` now uses a small `ReconnectPublication` packet:
  lifecycle/generation acceptance, reconnect request registration, active-client
  detachment, and state mutation are decided under `@lifecycle_lock`; state/log
  fanout runs after that lock is released.
- The deterministic reconnect-vs-stop spec still proves the exact interleaving:
  reconnect observes a live supervisor, the test hook pauses it, `stop`
  completes, reconnect resumes, and stale public reconnect state remains
  unobservable.
- `StateStore` now exposes a payload-producing reconnect mutation so callers can
  mutate authoritative state under their own lock and defer subscriber fanout.
- A new liveness spec proves `stop` reaches stopped lifecycle state while
  reconnect state publication is blocked.
- `TODO.md` now distinguishes the sequential post-stop reconnect proof from the
  concurrent paused-live-then-stop proof.
- `ReconnectSignal#on_waiter_registered` documents its lock contract:
  callbacks run while `@lock` is held, must not block, and must not send on an
  unbuffered channel.
- `ReconnectSignal::WaitResult` remains explicit with
  `Requested(epoch)`, `Interrupted(epoch)`, `TimedOut(epoch)`, and
  `Cancelled(epoch)`.
- Strict Rust compatibility remains manual/scheduled until `obsctl-rs` owns a
  matching contract fixture root.

Reviewer findings from the latest pass:

- No regression was found in the targeted stale-publication race: stop-wins
  reconnect remains generation-safe.
- The lifecycle-lock liveness direction is correct: synchronous IPC/log fanout
  no longer runs inside `@lifecycle_lock`.
- The new liveness spec proves lifecycle progress, but not full shutdown
  cleanup. `publish_reconnect` currently publishes state/log callbacks before
  closing the detached OBS client; if state/log fanout blocks forever, `stop`
  can return while the old OBS WebSocket remains open.
- Detached-client cleanup is not protected by `ensure`; an unexpected exception
  from a publication callback could skip closing the detached client.
- `StateStore#mark_reconnect_requested_payload` is useful but potentially
  misleadingly named: it mutates authoritative state and returns a payload. The
  API should make that mutation explicit and have focused specs.
- Remaining reconnect flake sources are unchanged: some reconnect specs still
  depend on unavailable-then-bind port windows and `wait_for_disconnect` still
  polls.

## P0: Finish Reconnect Publication Cleanup Semantics

1. Close detached OBS clients before blockable publication fanout.
   - Keep the lifecycle acceptance and detachment decision under
     `@lifecycle_lock`.
   - After releasing the lifecycle lock, close the detached client before state
     or log callbacks that can block on IPC sockets or file IO.
   - Do not reintroduce client close, subscriber fanout, socket writes, or file
     logging inside `@lifecycle_lock`.

2. Guarantee detached-client cleanup when publication fails.
   - Wrap reconnect publication in an `ensure` or equivalent so the detached OBS
     client is closed even if a state/log callback raises unexpectedly.
   - Keep public error behavior safe and secret-free if publication exceptions
     are surfaced or logged.

3. Strengthen the liveness regression spec.
   - In the blocked-publication test, assert the old OBS WebSocket close is
     observed before or independently of publication release.
   - Add a variant where log fanout blocks, not only state fanout.
   - Add a publication-raises case proving detached-client cleanup still
     happens.

4. Clarify the state-store deferred-payload API.
   - Rename or document the method so callers understand it mutates state and
     returns a precomputed IPC payload.
   - Add focused `StateStore` specs proving the returned payload matches
     `snapshot_json`, telemetry changes are applied once, and callbacks are not
     invoked until `publish_snapshot_payload`.

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

1. Close detached OBS clients before blockable reconnect publication fanout, and
   guarantee cleanup if publication callbacks raise.
2. Strengthen blocked-publication specs to assert OBS client closure and cover
   both state and log fanout blockers.
3. Add focused `StateStore` specs for deferred reconnect payload semantics.
4. Replace remaining reconnect unavailable-then-bind and polling surfaces with
   deterministic fake-server probes.
5. Add or coordinate the Rust-side `obsctl-rs` contract fixtures, then run
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
