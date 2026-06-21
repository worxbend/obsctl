# obsctl Improvement Plan

This plan reflects a fresh reviewer pass on the 2026-06-21 reconnect proof
slice. The touched focused specs are green, but the main reconnect-vs-stop race
is not fully closed.

## Current Assessment

`obsctl` has a mature local daemon architecture: one server owns the OBS
WebSocket session, thin CLI/TUI clients use Unix socket IPC, public CLI/IPC
contracts are fixture-backed, reconnect behavior has focused primitive specs,
and the default Crystal gate has recently been green at 255 examples.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Completed or already correct:

- `ReconnectSignal#on_waiter_registered` now documents its lock contract:
  callbacks run while `@lock` is held, must not block, and must not send on an
  unbuffered channel.
- `ReconnectSignal::WaitResult` is explicit and currently has four variants:
  `Requested(epoch)`, `Interrupted(epoch)`, `TimedOut(epoch)`, and
  `Cancelled(epoch)`.
- `ObsSupervisor` handles `Cancelled` structurally and breaks retry delay
  waiting without incrementing backoff.
- The new supervisor spec deterministically proves the simple post-stop path:
  `reconnect` called after `stop` returns `false` and does not mutate public
  state.
- Reviewer validation passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec spec/obsctl/server/reconnect_signal_spec.cr spec/obsctl/server/obs_supervisor_spec.cr`
  with 16 examples.
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test` also passed with
  255 examples.

Reviewer findings:

- No default-gate regression was found.
- The implementation does **not** fully prove or fix the original
  reconnect-vs-stop race. `ObsSupervisor#reconnect` checks lifecycle state under
  `@lifecycle_lock`, releases the lock, then registers the reconnect request and
  publishes `OBS reconnect requested`. A concurrent `stop` can still run between
  the lifecycle check and the public state mutation.
- The new `stopped_reconnect_attempted?` bit is useful test observability for
  reconnect calls made after stopped state, but it does not observe the
  interleaving where reconnect already captured a live `ReconnectSignal` before
  `stop`.
- `TODO.md` now overclaims this area by saying reconnect-after-stop behavior is
  proven before stale public state can be published. That statement is true only
  for the sequential post-stop path, not for the concurrent reconnect-vs-stop
  interleaving.
- The `on_waiter_registered` documentation change is correct and should stay.
- Remaining reconnect flake sources are unchanged: some reconnect specs still
  use unavailable-then-bind port windows and `wait_for_disconnect` still polls.
- Strict Rust compatibility remains manual/scheduled until `obsctl-rs` owns a
  matching contract fixture root.

## P0: Close Reconnect-Vs-Stop Truthfulness

1. Make `ObsSupervisor#reconnect` generation-safe through publication.
   - Carry the lifecycle generation alongside the captured `ReconnectSignal`.
   - Before calling `mark_reconnect_requested`, re-check that the same generation
     is still alive, or hold a lifecycle-gated critical section through request
     registration, client detachment, and public state mutation.
   - If `stop` wins after the initial liveness check, return `false` and do not
     publish `OBS reconnect requested`.
   - Preserve lock ordering: `@lifecycle_lock` before `@client_lock`, matching
     `stop` and `claim_client`.

2. Add an exact deterministic race spec.
   - Introduce a narrow test hook/barrier between reconnect's lifecycle check
     and public state mutation, or refactor reconnect into a helper whose
     generation token can be exercised directly.
   - The spec must prove this interleaving:
     reconnect observes a live supervisor, stop completes, reconnect resumes,
     reconnect returns `false`, state/telemetry remain unchanged, and no
     `obs_reconnect_requested` log is published.
   - Keep the current sequential post-stop spec as a separate simpler case.

3. Correct project trackers after the fix.
   - Update `TODO.md` so it does not claim the concurrent proof until the exact
     interleaving above is covered.
   - Keep `PLAN.md`, `MEMORY.md`, and `AGENT_LOG.md` aligned with the final
     behavior.

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
   - Add a deterministic helper that owns port reservation and delayed fake OBS
     startup.
   - Ensure the helper distinguishes accepted WebSocket connections from failed
     TCP attempts so probe names match what they observe.

2. Continue replacing polling/sleep-based reconnect specs.
   - Convert remaining reconnect tests to fake OBS probes for Identify received,
     close observed, request received, and no-attempt windows.
   - Replace the ad hoc `StateStore` subclass used as a pre-delay barrier with a
     narrower supervisor test hook if it remains useful after the race fix.

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

1. Fix `ObsSupervisor#reconnect` so stop cannot interleave after the liveness
   check and before public reconnect state is published; add an exact race spec.
2. Correct `TODO.md` once the concurrent reconnect-vs-stop proof is real.
3. Add deterministic unavailable-then-bind helpers and reduce reconnect specs'
   dependence on port races, polling, and fixed no-attempt sleeps.
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
