# obsctl Improvement Plan

This plan reflects the fresh reviewer pass on the iteration 10 reconnect-signal
hardening work (waiter-registration probe, WaitResult type, race witness spec,
and deterministic signal specs). The default Crystal gate is green at 255 examples.

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

Completed this iteration:

- `ReconnectSignal` now exposes a `WaitResult` abstract struct with three
  concrete subtypes: `Requested(epoch)`, `Interrupted(epoch)`, and
  `TimedOut(epoch)`. `wait()` returns `WaitResult` instead of a raw `UInt64`.
- `ObsSupervisor` uses the result type to distinguish durable reconnect requests
  (no backoff counter increment) from transient wakes and normal timeouts (backoff
  counter incremented).
- A test-only `on_waiter_registered` probe was added to `ReconnectSignal`, called
  under the lock immediately after appending a waiter. All concurrent-wake signal
  specs now use the probe instead of fixed-duration sleep-based inference.
- The reconnect-vs-stop race is documented and witnessed by a new supervisor spec
  that relies on Crystal's cooperative scheduler to guarantee `stop` wins before
  the spawned reconnect fiber runs. The spec's assertion is conditional on the
  outcome so it will not fail if the schedule unexpectedly reverses.
- All 6 signal specs and the stale-wake-vs-retry-delay suite now correctly test
  what they claim: during-wait vs before-wait cases are structurally separated.
- Full validation: 255 examples, 0 failures.

Validation for this iteration:

- Focused touched specs passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec spec/obsctl/server/reconnect_signal_spec.cr spec/obsctl/server/obs_supervisor_spec.cr`
  with 16 examples.
- Default validation passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  with 255 examples.
- Build passed: `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`.
- Lint target exited 0 through the existing "Ameba not installed" skip path.

Reviewer findings:

- No blocking default-gate regression was found.
- P0 items 1 (deterministic waiter-probe) and 2 (explicit WaitResult type) from
  the previous plan are fully implemented.
- P0 item 3 (reconnect-vs-stop truthfulness) is witnessed but not strictly
  proven: the spec conditional on `reconnect_result == false` only fires the hard
  assertion when stop wins the scheduler race, which is guaranteed only under
  Crystal's cooperative model. The assertion is vacuously satisfied when reconnect
  wins.
- `on_waiter_registered` is called while holding `@lock`. For buffered-channel
  callbacks this is safe; for blocking or unbuffered callbacks it would deadlock.
  The property documentation says "Test-only" but does not document the lock
  constraint.
- `Interrupted` is used for both transient internal wakes and cancel wakes. The
  supervisor differentiates them by calling `stopped?` after the result. This is
  correct and documented, but a `Cancelled` subtype would make the distinction
  structural rather than inferred.
- When `stop` wins the reconnect-vs-stop race, `reconnect` returns `false` before
  mutating any public state, so no stale `OBS reconnect requested` is published.
  This is the correct behavior, verified by the new spec.
- `wait_for_disconnect` still polls every 250 ms and reconnect specs still use
  `unused_tcp_port` for unavailable-then-bind scenarios. These are the remaining
  flake sources.
- The strict compatibility workflow remains manual/scheduled and still needs
  compatible Rust-side fixtures before it can become a required signal.

## P0: Close Remaining Reconnect Truthfulness Gaps

1. Harden the reconnect-vs-stop witness into a deterministic proof.
   - The current spec relies on Crystal's cooperative scheduler. Add a
     synchronization barrier so `stop` waits for the spawned `reconnect` fiber
     to observe the stopped state before the assertion runs. Alternatively, use
     the `@lifecycle_lock` to expose a "reconnect was attempted while stopped"
     observable bit rather than relying on scheduling order.
   - Consider adding a `Cancelled` subtype to `WaitResult` so the supervisor
     need not call `stopped?` to distinguish cancel wakes from transient wakes.

2. Document `on_waiter_registered` lock constraint.
   - Add a one-line comment to the property declaration noting that the callback
     is invoked under `@lock` and must not block or send on an unbuffered channel.
   - This prevents future deadlocks from accidental blocking callbacks in tests.

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

1. Document `on_waiter_registered` lock constraint and harden the reconnect-vs-stop
   witness into a deterministic proof (barrier or observable stopped-reconnect bit).
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
