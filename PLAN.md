# obsctl Improvement Plan

This plan reflects a fresh senior review of the 2026-06-21 iteration 10
contract externalization slice.

## Current Assessment

`obsctl` has a mature daemon-first control-plane shape: one server owns the OBS
WebSocket session, CLI/TUI clients communicate over Unix socket IPC, reconnect
behavior is strongly tested, and status/command contracts are fixture-backed.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Iteration 10 moved the cross-implementation contract in the right direction:

- Added `spec/fixtures/contracts/README.md` documenting the Crystal fixture
  root, required `cli/human/`, `cli/json/`, and `ipc/` directories, recognized
  Rust-side roots, opt-in strict compatibility, and finalized
  `dropped_reconnect_diagnostic_logs` semantics.
- Added `spec/fixtures/contracts/contract_manifest.yml` listing the portable
  public fixtures and marking status fixtures that include reconnect diagnostic
  drop telemetry.
- Added `scripts/bootstrap_obsctl_rs_contract_fixtures` and a Makefile target
  to copy the Crystal contract root into a sibling `obsctl-rs` checkout.
- Updated strict `obsctl-rs` compatibility checks to validate the manifest,
  required directories, manifest-listed counterparts, manifest equality, and
  manifest-listed content before comparing fixtures.

Reviewer findings from this pass:

- Targeted contract compatibility specs pass:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec spec/obsctl/contracts`
  completed with 68 examples and 0 failures.
- The bootstrap helper copies the manifest, README, `cli/human/`, `cli/json/`,
  and `ipc/` fixture directories into `spec/fixtures/contracts/` in a target
  checkout.
- High-priority gap: three active root-level fixtures are still read by
  contract specs but are omitted from the new manifest and bootstrap export:
  `cli_status_success.json`, `cli_scene_error.json`, and
  `ipc_set_scene_request.json`. Strict compatibility now ignores these active
  public contract fixtures.
- The bootstrap helper always writes `spec/fixtures/contracts/` in `obsctl-rs`.
  If Rust already owns a different recognized root, such as
  `tests/fixtures/contracts/`, the helper can create a higher-precedence copied
  root that strict compatibility checks instead of the Rust-owned root.
- Manifest validation is useful but still shallow: it does not validate
  manifest path safety, category/path consistency, duplicate relative paths,
  behavior names, telemetry flags, or that every fixture referenced by contract
  specs is listed.
- Strict comparison currently requires byte-identical manifests. That is fine
  for a copied Crystal manifest, but it should be an explicit decision if
  Rust-side metadata such as `fixture_root` is ever allowed to differ while the
  public fixture list remains equivalent.

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
   - Command-executor, CLI, server, helper, and golden contract specs cover the
     field and its bounded-fanout source.

## Completed P0: Status Telemetry Contract

1. Clarify missing versus zero drop-count semantics.
   - Older daemon payloads missing `dropped_reconnect_diagnostic_logs` render as
     `-` in human output.
   - Present values render as the daemon-reported integer, including `0`.
   - JSON output remains faithful to the daemon payload and does not synthesize
     missing fields.
   - Combined `status --json` and daemon-only `server-status --json` both have
     direct older-daemon omitted-field coverage.

2. Document counter lifecycle and scope.
   - The counter is process-local runtime telemetry.
   - It resets on daemon restart.
   - It counts only dropped secondary reconnect diagnostic `logs` topic fanout
     deliveries from the bounded helper.
   - It does not count ordinary state/event/log subscriber drops or primary
     runtime logger writes.

3. Make the numeric contract explicit.
   - Public status serialization reports a non-negative signed JSON integer.
   - Internal `UInt64` values larger than `Int64::MAX` saturate to
     `Int64::MAX`.
   - Specs cover positive, default-zero, and saturation behavior.

4. Localize formatter failures.
   - Direct human formatter specs assert present non-zero values for combined
     `status` and daemon-only `server-status`.
   - Golden fixtures still freeze the current public output shape.

## Completed P1: Reconnect Determinism

1. Retire server reconnect unavailable-then-bind port races.
   - `SpecSupport::TcpGate` reserves a port without listening, causing
     connection attempts to fail immediately while preserving ownership.

2. Add connection-specific fake OBS close probes.
   - Fake OBS assigns accepted WebSocket ids.
   - Specs assert the specific detached connection closes.

3. Make established disconnect waiting event-driven first.
   - `OBS::Client#wait_for_close` exposes sanitized terminal close/error
     notification.
   - `ObsSupervisor#wait_for_disconnect` waits on that notification before the
     fallback timeout and keeps event draining.

## P0: Repair Portable Contract Export

1. Resolve the active root-level fixture gap.
   - Decide whether `cli_status_success.json`, `cli_scene_error.json`, and
     `ipc_set_scene_request.json` remain public contracts.
   - If yes, migrate them into `cli/json/` and `ipc/`, update their specs, list
     them in `contract_manifest.yml`, and ensure the bootstrap helper copies
     them.
   - If no, delete the legacy specs/fixtures or rewrite those specs to use the
     newer golden fixture tree.
   - Add a manifest completeness spec proving every fixture exercised by
     contract specs is manifest-listed or intentionally excluded.

2. Add manifest self-validation.
   - Validate duplicate `relative_path` entries.
   - Validate that each path is relative, contains no `..`, and lives under one
     required directory.
   - Validate `category` matches the path prefix.
   - Validate `behavior` names exist in the manifest `behaviors` map.
   - Validate telemetry flags for status/server-status fixtures that include
     `dropped_reconnect_diagnostic_logs`.

3. Make bootstrap root selection explicit.
   - If a destination repo already has a recognized fixture root, use that root
     or require an explicit target-root option.
   - Do not silently create `spec/fixtures/contracts/` when that would shadow an
     existing `tests/fixtures/contracts/` or `fixtures/contracts/` root.
   - Print the selected root and whether files were created or overwritten.

4. Add bootstrap safety and verification.
   - Add a dry-run or check mode that reports pending copies without changing
     the Rust checkout.
   - Add a post-copy verification mode that runs the manifest validation against
     the selected destination root.
   - Consider copying via a temporary directory plus rename for partial-copy
     resilience.

## P0: Finish Rust-Side Fixture Ownership

1. Coordinate the Rust-side shared fixture root.
   - Create or update one recognized root in `obsctl-rs`:
     `spec/fixtures/contracts/`, `tests/fixtures/contracts/`, or
     `fixtures/contracts/`.
   - Populate the README, manifest, `cli/human/`, `cli/json/`, and `ipc/`
     fixtures after the manifest/export gap above is fixed.
   - Include the finalized `dropped_reconnect_diagnostic_logs` status semantics.

2. Run strict compatibility in a prepared dual-repo workspace.
   - Use `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make contract-rs-compat`.
   - Treat content differences as public-contract decisions, not mechanical
     churn.
   - Keep default `make test` deterministic in single-repo and accidental
     sibling-checkout workspaces.

3. Decide promotion policy after Rust fixtures pass.
   - Scheduled/manual strict compatibility may be enough while Rust is catching
     up.
   - Promote to a required PR signal only after both repositories own the same
     fixture contract and the helper cannot mask a Rust-owned root.

## P1: Mixed-Version Contract Fixtures

1. Add explicit older-daemon omitted-telemetry fixtures only if mixed-version
   CLI/server behavior should become a frozen fixture contract.
2. Keep current-daemon success fixtures separate from older-daemon
   compatibility fixtures.
3. Replace repeated inline status JSON setup with narrow builders if status
   grows again.

## P1: Remaining Reconnect Test Polish

1. Document or broaden `OBS::Client#wait_for_close`.
   - Today one supervisor waiter is the only production consumer.
   - If concurrent waiters appear, replace the single notification with a
     condition-style primitive or per-waiter channels.

2. Continue replacing polling/sleep-based reconnect specs.
   - Convert remaining elapsed-time/no-event assertions to fake OBS probes where
     practical.
   - Keep fallback sleeps only where the behavior under test is explicitly
     "nothing happened during this interval".

3. Clarify fake OBS probe naming and usage.
   - Keep `connection_attempt_count` documented as accepted WebSocket
     connections.
   - Prefer connection-id assertions for overlapping reconnect specs.

## P1: Broader Slow-Subscriber Policy

1. Decide whether `BestEffortLogBroadcast` should become a broader primitive.
   - Ordinary state/log/event broadcasts still use synchronous
     `ClientRegistry#broadcast`.
   - A registry-level policy should drop, evict, or bound slow sessions rather
     than blocking command paths indefinitely.

2. Preserve runtime logging as the durable sink.
   - Keep reconnect diagnostics out of `Server#broadcast_log` when the runtime
     logger has already written them.
   - Keep secret redaction before every public or persisted diagnostic surface.

## P1: Main CI And Validation Polish

1. Add main CI for the Crystal gates:
   - `crystal tool format --check`
   - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache crystal spec`
   - `crystal build src/obsctl.cr -o bin/obsctl`
   - `make lint` or Ameba when dependencies are installed

2. Make lint meaningful in CI.
   - Decide whether Ameba should be a development dependency.
   - If yes, install it in CI and fail on lint issues.
   - If no, keep the skip explicit and documented.

## P1: Config And Security

1. Reject unknown nested config fields.
2. Add `obsctl doctor`.
3. Add config migration/explain/diff commands.
4. Keep secrets out of logs, IPC errors, JSON envelopes, TUI panels, specs, and
   fixtures.

## P2: Product Features

Add breadth only after daemon/IPC/reconnect contracts and cross-implementation
fixtures remain stable.

1. Recording controls: `record start|stop|pause|resume|status`.
2. Streaming controls: `stream start|stop|status`.
3. Replay buffer and virtual camera controls.
4. Scene/source operations, transitions, screenshots, profiles, and scene
   collections.
5. Script-friendly event stream: `obsctl watch`, `obsctl watch --json`,
   newline-delimited JSON, topic filters.
6. Macros for scene/audio/wait/record/stream action sequences.

## P2: TUI Upgrade

1. Treat the TUI as an operator dashboard.
2. Improve command palette ergonomics.
3. Add recovery UX for daemon unavailable states.

## P3: Open Source Polish

1. Add release packaging.
2. Improve docs: architecture, IPC protocol, CLI contract, security model,
   contributor guide, recipes, and demo media.
3. Decide the two-project strategy for Crystal and Rust.

## Suggested Next Pull Requests

1. Repair the portable contract manifest/export gap for active root-level
   fixtures.
2. Make bootstrap root selection explicit so it cannot shadow an existing
   Rust-owned fixture root.
3. Add manifest self-validation and a completeness spec.
4. Coordinate the Rust-side fixture root and run `make contract-rs-compat` in a
   prepared dual-repo workspace.
5. Continue reconnect test polish and slow-subscriber policy work after the
   contract export is sound.

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
