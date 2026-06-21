# obsctl Improvement Plan

This plan reflects a fresh senior review of the 2026-06-21 reconnect-vs-stop
truthfulness slice. The implementation closes the targeted stale-publication
race and adds a deterministic interleaving spec. The next highest-risk item is
to keep that linearizability guarantee while removing synchronous IPC/log
callbacks from the supervisor lifecycle lock.

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

- `ObsSupervisor#reconnect` now captures the live generation, pauses only through
  a test hook, and re-checks lifecycle state, generation, and reconnect-signal
  identity before accepting the reconnect request.
- When `stop` wins after reconnect observed a live generation, `reconnect`
  returns `false`, does not request reconnect, does not detach/close another
  client, does not mutate state/telemetry, and does not publish the
  `obs_reconnect_requested` log.
- The deterministic supervisor spec now covers the exact interleaving:
  reconnect observes a live supervisor, the spec pauses it, `stop` completes,
  reconnect resumes, and stale public reconnect state remains unobservable.
- The earlier sequential post-stop spec remains useful and separate.
- `ReconnectSignal#on_waiter_registered` documents its lock contract:
  callbacks run while `@lock` is held, must not block, and must not send on an
  unbuffered channel.
- `ReconnectSignal::WaitResult` remains explicit with
  `Requested(epoch)`, `Interrupted(epoch)`, `TimedOut(epoch)`, and
  `Cancelled(epoch)`.
- Strict Rust compatibility remains manual/scheduled until `obsctl-rs` owns a
  matching contract fixture root.

Reviewer findings from the latest pass:

- No implementation regression was found in the targeted reconnect-vs-stop
  behavior. The core race from the previous review is closed in the reviewed
  code path.
- The new deterministic spec is materially stronger than the previous witness:
  it uses `test_reconnect_before_publication` as a real barrier and makes the
  stop-wins outcome mandatory, not conditional.
- `TODO.md` was corrected before the race spec landed and now underclaims the
  current proof by still saying the exact concurrent spec is missing. It should
  be aligned with the final state of this slice.
- `ObsSupervisor#reconnect` now calls `StateStore#mark_reconnect_requested` and
  `publish_log` while holding `@lifecycle_lock`. Those callbacks can fan out to
  `ClientRegistry#broadcast`, which synchronously writes to IPC client sockets.
  This preserves the publication invariant but expands a lifecycle critical
  section around potentially blocking IO.
- The public `test_reconnect_before_publication` hook is acceptable as a narrow
  internal test seam, but it should remain documented as test-only and should
  not become part of the production control surface.
- Remaining reconnect flake sources are unchanged: some reconnect specs still
  depend on unavailable-then-bind port windows and `wait_for_disconnect` still
  polls.

## P0: Keep Reconnect Publication Linearizable Without Blocking Lifecycle

1. Split reconnect acceptance from synchronous publication side effects.
   - Keep the generation/lifecycle decision, reconnect request registration,
     active-client detachment, and state mutation linearized under
     `@lifecycle_lock`.
   - Do not run subscriber fanout, socket writes, or file logging while holding
     `@lifecycle_lock`.
   - Preferred shape: refactor state/log publication into a small accepted
     reconnect result containing the detached client and payloads to broadcast
     after the lifecycle lock is released, or make broadcast dispatch
     non-blocking behind an event queue.

2. Add a regression spec for lifecycle-lock callback safety.
   - Simulate a subscribed client or test callback that blocks on state/log
     publication.
   - Prove `stop` is not prevented from reaching stopped state by a blocked
     subscriber write or log fanout.
   - Preserve the existing stop-wins reconnect-vs-stop spec while adding this
     liveness check.

3. Align project trackers after the completed race proof.
   - Update `TODO.md` so it credits the exact deterministic concurrent
     reconnect-vs-stop spec now present.
   - Keep the distinction between the sequential post-stop proof and the
     concurrent paused-live-then-stop proof.

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

1. Decouple reconnect lifecycle publication from synchronous IPC/log callbacks
   while preserving the stop-wins invariant.
2. Correct `TODO.md` to reflect that the exact concurrent reconnect-vs-stop spec
   now exists and passes.
3. Replace remaining reconnect unavailable-then-bind and polling surfaces with
   deterministic fake-server probes.
4. Add or coordinate the Rust-side `obsctl-rs` contract fixtures, then run
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
