# obsctl Improvement Plan

This plan reflects the fresh reviewer pass on the June 20, 2026 iteration 6
reconnect-control and compatibility-CI work. The default Crystal gate is green,
strict `obsctl-rs` compatibility is no longer an always-on push/PR gate, and
explicit reconnect now wakes retry backoff when the supervisor is alive.

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

- `.github/workflows/obsctl-rs-compat.yml` now runs through manual
  `workflow_dispatch` and a scheduled cadence instead of push/pull-request
  triggers. The Rust repository owner, name, and ref are configurable through
  workflow inputs or repository variables.
- `ObsSupervisor#start` now marks the supervisor alive synchronously with an
  explicit lifecycle state, ignores double `start` calls while alive, and
  `stop` marks the supervisor stopped before closing the active client.
- `obsctl reconnect` still rejects stopped supervisors with `OBS_UNAVAILABLE`,
  but live supervisors now wake retry backoff promptly when OBS is unavailable.
- The fake OBS server now exposes deterministic probes for accepted WebSocket
  connections, Identify frames, OBS request types, close notifications, and
  no-attempt windows.
- Server integration coverage proves the wakeable reconnect path: OBS is
  unavailable, reconnect is enabled with a long backoff, OBS appears, an IPC
  `reconnect_obs` request wakes the loop, Identify is sent promptly, and
  combined status reports the reconnected state.
- README, command docs, protocol docs, and `TODO.md` were refreshed for the
  opt-in strict compatibility workflow and wakeable reconnect contract.

Validation observed during review:

- Focused touched specs passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec spec/obsctl/server/obs_supervisor_spec.cr spec/obsctl/server/server_spec.cr`
  with 21 examples.
- Default validation passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  with 244 examples.
- The implementation log reports `make format`, `make build`, and `make lint`
  passing; `make lint` still uses the existing Ameba-not-installed skip path.
- Strict `make contract-rs-compat` still requires a prepared dual-repo
  workspace with compatible `obsctl-rs` fixtures before it can become a
  required signal.

Reviewer findings:

- No blocking default-gate regression was found.
- The reconnect-disabled false-success path remains fixed, and reconnect while
  alive in retry backoff now attempts OBS promptly instead of waiting out the
  configured delay.
- The new fake OBS probes are useful and reduce several sleep-heavy assertions,
  but they currently count accepted WebSocket connections rather than failed TCP
  connection attempts; absence assertions should be interpreted accordingly.
- `ObsSupervisor` lifecycle state is clearer than before, but stop-then-start
  reuse is not generation-safe. After `stop` sets the global state to
  `Stopped`, a quick `start` can set it back to `Starting`/`Running` before the
  old fiber exits. The old fiber's `stopped?` check is not generation-scoped, so
  it can continue and race the new fiber.
- Wake signals are buffered on a single channel shared across the supervisor
  lifetime. A wake emitted while no delay is waiting can become stale and make a
  later backoff return immediately. This is probably harmless for the current
  server lifecycle, but it weakens the exact retry-delay contract.
- Reconnect monitoring still uses polling inside `wait_for_disconnect`
  (`sleep 250.milliseconds`), so reconnect after dropping an active client is
  prompt but not fully event-driven.
- The strict compatibility workflow is now scoped correctly for this repository,
  but scheduled runs will continue to fail until `obsctl-rs` publishes a
  recognized fixture root with matching `cli/` and `ipc/` counterparts.

## P0: Make Supervisor Lifecycle Generation-Safe

1. Fix stop-then-start reuse or explicitly make supervisors single-use.
   - Preferred: pass the lifecycle generation into the run loop and make
     `stopped?` generation-aware, so an old fiber exits even if a newer
     generation has already started.
   - Clear any stale wake token when starting a new generation.
   - Add coverage for `start`, `stop`, immediate `start`, and prove only one OBS
     connection owner remains active.

2. Separate wake reasons from lifecycle state.
   - Replace the shared buffered `Channel(Nil)` with a small per-generation
     signal object or a channel recreated on each `start`.
   - Drain or invalidate stale wake tokens after reconnect requests that close
     an active client but do not enter a backoff wait.
   - Add a spec proving a stale wake does not skip the next scheduled retry
     unless a new explicit reconnect was requested.

3. Keep stopped-supervisor behavior as an explicit public error.
   - Preserve `OBS_UNAVAILABLE` for exited supervisors unless a deliberate
     one-shot reconnect feature is added.
   - If one-shot reconnect is added later, expose it as a clear state
     transition with tests proving a real OBS connection attempt starts.

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

1. Continue replacing polling/sleep-based reconnect specs.
   - Convert remaining reconnect tests from generic polling helpers to fake OBS
     probes for Identify received, close observed, request received, and
     no-attempt windows.
   - Keep polling only for state-store changes that are inherently asynchronous
     across IPC.

2. Remove `unused_tcp_port` races from reconnect specs.
   - Add a deterministic unavailable-then-bind helper that owns port selection
     and delayed fake-server startup.
   - Prefer helpers that reserve the intended port until the exact test moment
     when OBS should become reachable.

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

1. Make `ObsSupervisor` generation-safe around stop/start and stale wake tokens.
2. Add or coordinate the Rust-side `obsctl-rs` contract fixtures, then run
   `make contract-rs-compat` in a prepared dual-repo workspace.
3. Replace the remaining reconnect polling and `unused_tcp_port` helpers with
   deterministic fake OBS probe and delayed-bind helpers.

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
