# obsctl Improvement Plan

This plan reflects the fresh reviewer pass on the June 20, 2026 iteration 9
reconnect-signal hardening work. The default Crystal gate is green, and the
previously identified primitive-level check-then-wait lost-wake window in
`Server::ReconnectSignal#wait` has been closed.

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

Completed in iteration 9:

- `Server::ReconnectSignal` was moved into its own file and now registers a
  waiter under the same mutex as the request-epoch check.
- Explicit reconnect requests still advance durable generation-scoped epochs.
- Transient internal wakes and stop/cancel wakes still interrupt a current wait
  without advancing the explicit reconnect epoch.
- Stale notifications no longer survive to skip later unrelated retry delays.
- Focused signal specs now cover request-before-wait, request-during-wait,
  handled-request stale wake behavior, internal wake, cancel wake, and repeated
  request epochs.
- README, command docs, protocol docs, `TODO.md`, and `MEMORY.md` remain aligned
  around the public reconnect contract rather than internal wake taxonomy.

Validation reported for iteration 9:

- Focused touched specs passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec spec/obsctl/server/reconnect_signal_spec.cr spec/obsctl/server/obs_supervisor_spec.cr`
  with 15 examples.
- Formatting passed: `make format`.
- Default validation passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  with 254 examples.
- Build passed: `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`.
- Lint target exited 0 through the existing "Ameba not installed" skip path.

Reviewer findings:

- No blocking default-gate regression was found.
- The concrete implementation fixes the reported atomicity gap: once
  `wait` has checked the request epoch and decided to sleep, the waiter is
  already visible to a concurrent `request`, `wake`, or `cancel`.
- The signal primitive is small and fits the supervisor architecture better as
  a separate unit than as a nested private class.
- The tests are useful but not fully deterministic: the "current waiter" cases
  send a `started` signal before `wait` has actually registered its waiter and
  then rely on a short no-result timeout. On a slow scheduler, those cases can
  accidentally prove request-before-wait behavior instead of request-during-wait
  behavior.
- `ReconnectSignal#wait` returns only an epoch. The caller must infer timeout,
  transient wake, and cancel from external lifecycle state because all three can
  return the handled epoch. That is currently sufficient for `ObsSupervisor`,
  but it is a weak contract for future changes.
- A narrow reconnect-vs-stop race still exists conceptually: `reconnect` can
  take a signal from a live supervisor and then race with `stop` before it marks
  state as `OBS reconnect requested`. This is not a new iteration-9 regression,
  but it is the next lifecycle truthfulness gap worth pinning down.
- `wait_for_disconnect` still polls every 250 ms. Reconnect correctness is much
  better, but stop/reconnect responsiveness and tests still depend on polling.
- Reconnect specs still use `unused_tcp_port` for unavailable-then-bind
  scenarios, so the remaining flake surface is smaller but not eliminated.
- The strict compatibility workflow remains manual/scheduled and still needs
  compatible Rust-side fixtures before it can become a required signal.

## P0: Strengthen Reconnect Synchronization Proof

1. Make signal-level tests deterministic at the waiter-registration boundary.
   - Add a test-only probe or narrow synchronization hook that fires after
     `ReconnectSignal#wait` has appended its waiter under the lock.
   - Use that probe for request-during-wait, internal-wake-during-wait, and
     cancel-during-wait specs instead of relying on short no-result sleeps.
   - Keep request-before-wait as a separate case so the two guarantees cannot be
     accidentally conflated.

2. Make wait outcomes explicit.
   - Replace the raw `UInt64` return from `wait` with a small result type or
     enum-backed struct, for example `Requested(epoch)`, `Interrupted(epoch)`,
     and `TimedOut(epoch)`.
   - Preserve the invariant that only explicit requests advance epochs.
   - Update `ObsSupervisor` so retry logic documents why each outcome causes an
     immediate retry, a normal timeout retry, or a stop-driven loop exit.

3. Pin down reconnect-vs-stop truthfulness.
   - Add a focused supervisor spec for `reconnect` racing with `stop`.
   - Ensure a stopped generation cannot publish `OBS reconnect requested` after
     `stop` has won the lifecycle lock.
   - If the race is observed, make `reconnect` re-check generation/liveness
     before changing public state or returning success.

## P0: Finish Strict Compatibility Fixture Ownership

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
   - Promote the "connection attempt failed and delay is about to start" hook
     out of the ad hoc `StateStore` subclass if it remains useful, or replace it
     with a smaller supervisor test hook that does not overload state storage.
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

1. Make `ReconnectSignal` specs deterministic at the waiter-registration
   boundary and consider explicit wait-result types.
2. Add deterministic unavailable-then-bind helpers and reduce reconnect specs'
   dependence on `unused_tcp_port`, polling, and fixed no-attempt sleeps.
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
