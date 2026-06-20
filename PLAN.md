# obsctl Improvement Plan

This plan reflects the fresh reviewer pass on the June 20, 2026 iteration 5
truthful-reconnect work. The default Crystal gate is green in the current
workspace, explicit reconnect no longer reports success after the supervisor
has exited, and reconnect timestamp semantics are now documented and covered by
focused specs.

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

- `obsctl reconnect` now checks supervisor liveness before reporting success.
  If the supervisor loop has exited, the server returns `OBS_UNAVAILABLE` with
  the public message
  `OBS supervisor is not running; restart the server or enable reconnect.`
- `ObsSupervisor` exposes `alive?` lifecycle state and returns a boolean from
  `reconnect`, allowing `CommandExecutor` to distinguish a real reconnect
  request from a stopped-supervisor no-op.
- Integration coverage now proves the reconnect-disabled startup-failure case:
  OBS unavailable at startup, `reconnect.enabled: false`, supervisor exits, OBS
  later appears, and `reconnect_obs` fails without sending an OBS Identify.
- Focused `StateStore` specs freeze reconnect timestamp semantics:
  `last_disconnected_at` records connected-to-disconnected transitions;
  `last_connection_failed_at` records the most recent failed connection attempt
  and persists across later successful connections.
- CLI unit specs now assert all reconnect timestamp fields for combined status,
  daemon-only status, human output, and JSON envelopes, while remaining tolerant
  of older daemon payloads missing `last_connection_failed_at`.
- Strict `obsctl-rs` compatibility diagnostics now print the selected sibling
  repository and fixture root, and missing-root errors explain the expected
  `cli/` and `ipc/` fixture layout.
- README, command docs, protocol docs, and `TODO.md` were refreshed for the
  reconnect liveness and timestamp contract.

Validation observed during review:

- Focused touched specs passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec ...`
  with 72 examples.
- Default validation passed:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  with 240 examples.
- Strict compatibility intentionally failed in this workspace because
  `/home/worxbend/Worxpace/obsctl-rs` has no recognized contract fixture root.
  The failure is now actionable and lists the expected roots and fixture layout.

Reviewer findings:

- No blocking default-gate regression was found.
- The reconnect-disabled false-success bug is fixed for the exited-supervisor
  path.
- `last_connection_failed_at` is now a historical "most recent failed attempt"
  field by contract; successful connections intentionally do not clear it.
- `ObsSupervisor#alive?` is useful but still a coarse lifecycle signal. There is
  a small startup/stop race window because `alive?` is set by the spawned fiber,
  not synchronously by `start`.
- A reconnect request while the supervisor is alive but sleeping between retry
  attempts records `"OBS reconnect requested"` but does not wake the retry loop
  immediately. That is truthful enough for "the supervisor can act eventually,"
  but it is not yet an operator-friendly "attempt now" command.
- The strict `obsctl-rs` GitHub workflow remains always-on. It will be red until
  the Rust repository has compatible fixtures, even though the local strict
  failure message is now clear.
- Reconnect and server integration specs still use polling loops, sleeps, and an
  `unused_tcp_port` helper. They pass, but deterministic fake-server probes
  would reduce flake risk around absence/presence of connection attempts.

## P0: Make Strict Compatibility CI Actionable

1. Decide how the `obsctl-rs` compatibility workflow should run before it
   becomes a required signal.
   - If strict compatibility is required on every push/PR, add compatible
     `cli/` and `ipc/` contract fixtures to `obsctl-rs` first.
   - If the Rust repository is not ready, change the workflow to
     `workflow_dispatch`, scheduled/manual, or a clearly named non-required job
     until fixtures exist.
   - Consider making the sibling repository configurable with a workflow input
     or repository variable instead of hardcoding `w0rxbend/obsctl-rs`.

2. Add or coordinate the Rust-side shared fixture root.
   - Create one recognized root in `obsctl-rs`:
     `spec/fixtures/contracts/`, `tests/fixtures/contracts/`, or
     `fixtures/contracts/`.
   - Populate matching `cli/human/`, `cli/json/`, and `ipc/` fixtures.
   - Run `make contract-rs-compat` in a prepared dual-repo workspace and treat
     content differences as real public-contract decisions.

3. Keep strict compatibility separate from the default gate.
   - The default suite must remain deterministic in single-repo and accidental
     sibling-checkout workspaces.
   - Strict compatibility should fail loudly only in explicitly prepared
     dual-repo contexts.

## P0: Tighten Supervisor Lifecycle Semantics

1. Make supervisor lifecycle state explicit enough to avoid edge races.
   - Consider setting an intermediate `starting` or `running` state
     synchronously in `start`, then transitioning to `stopped` in the fiber
     ensure block.
   - Guard against accidental double `start` calls or document that supervisors
     are single-start objects.
   - Add unit coverage for reconnect immediately after `start` and during
     `stop`.

2. Decide whether `obsctl reconnect` should wake the retry loop immediately.
   - Current behavior reports success when the supervisor loop is alive, even if
     it is sleeping before the next retry.
   - A more operator-friendly command would interrupt the backoff sleep or send a
     reconnect signal channel to the supervisor loop.
   - Add coverage for `reconnect.enabled: true`, OBS unavailable, supervisor
     alive in retry backoff, then explicit reconnect after OBS becomes
     available.

3. Keep stopped-supervisor behavior as an explicit public error.
   - Preserve `OBS_UNAVAILABLE` for exited supervisors unless a deliberate
     one-shot reconnect feature is added.
   - If one-shot reconnect is added later, expose it as a clear state transition
     with tests proving a real OBS connection attempt starts.

## P1: Test Determinism And Main CI

1. Continue replacing polling/sleep-based reconnect specs.
   - Extend the fake OBS server with deterministic probes for connection
     attempt started, Identify received, close observed, reconnect attempt
     completed, and no-attempt windows.
   - Prefer channels over fixed `sleep 50.milliseconds` loops where practical.
   - Avoid `unused_tcp_port` races by adding a fake-server or socket helper that
     can reserve or intentionally delay binding more deterministically.

2. Add main CI for the Crystal gates.
   - `crystal tool format --check`
   - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec`
   - `crystal build src/obsctl.cr -o bin/obsctl`
   - `make lint` or Ameba when dependencies are installed

3. Add a small lifecycle-focused spec layer.
   - Cover `ObsSupervisor#alive?` around start, clean stop, startup failure,
     reconnect-disabled exit, and retry-enabled backoff.
   - Keep these specs mostly unit-level so integration tests do not carry all
     lifecycle proof.

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

1. Make strict compatibility CI conditional/manual until `obsctl-rs` has the
   expected fixture root, or add the Rust-side fixtures and keep the workflow
   required.
2. Add a reconnect wake/signal path so explicit reconnect interrupts retry
   backoff, with coverage for retry-enabled OBS-unavailable startup.
3. Replace the highest-risk reconnect polling specs with deterministic fake OBS
   probes.

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
