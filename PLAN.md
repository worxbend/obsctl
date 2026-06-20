# obsctl Improvement Plan

This plan reflects the fresh reviewer pass on the June 20, 2026
contract-freeze/runtime-hardening closeout. The daemon-first architecture and
public CLI/IPC contract are now substantially locked and pass the current
Crystal gates. The remaining highest-value work is to reconcile a small
status-contract mismatch, preserve better reconnect/protocol-error telemetry,
and then move into product polish.

## Current Assessment

`obsctl` is a serious local OBS controller with a daemon, Unix socket IPC, thin
CLI/TUI clients, service installation, config dump/validation, a fake OBS
server, golden public-contract fixtures, and 209 passing Crystal specs.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Completed in the latest closeout iteration:

- JSON mode policy is explicit: exactly one machine JSON envelope on stdout,
  with secret-free warnings allowed on stderr.
- Unsupported JSON commands such as `init` and `service` now fail before side
  effects with a JSON `COMMAND_PARSE_ERROR` envelope and exit `5`.
- Invalid global options can still return JSON errors when `--json` is present.
- Public IPC/domain error mapping is covered by an audited table spec,
  including `ALIAS_AMBIGUOUS` as command parse exit `5`.
- IPC error redaction now covers quoted values, YAML-like `password: value`
  fields, and natural-language secret phrases.
- Architecture boundary specs now scan normal CLI, TUI, IPC, domain, and
  support layers, with explicit exceptions for the embedded TUI OBS adapter
  and server OBS supervisor.
- The embedded direct TUI adapter require contract is tested:
  `obs_session_client` is the explicit opt-in require path.
- Golden fixtures now cover every current proxy command for human output, JSON
  envelopes, and IPC request payloads.
- Optional `../obsctl-rs` fixture compatibility checks skip when the sibling
  project or fixture directory is absent.
- OBS protocol errors now explicitly close the websocket, fail pending
  requests nonblocking, and are covered by malformed-frame and parser-error
  specs.
- Server integration coverage proves IPC remains available and the supervisor
  reconnects after protocol-error-triggered client closure.
- Validation passed independently in review:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` with the existing Ameba-not-installed skip path

Reviewer findings:

- No blocking regression was found in the current implementation.
- The new golden fixtures freeze current `obsctl status` behavior as the same
  OBS-only payload as `obs-status`. That matches current code, but it conflicts
  with the broader acceptance text that says `obsctl status` should report
  both server and OBS status. This should be resolved before treating the
  fixture as a final compatibility promise.
- Protocol-error cleanup is operationally correct, but the supervisor-visible
  state records the eventual `"OBS WebSocket closed"` rather than preserving
  the original malformed-frame or parser-error cause. This weakens operator
  diagnostics and should be fixed alongside reconnect-status telemetry.
- Optional Rust compatibility checks are useful but weak: if `../obsctl-rs`
  exists without a recognized fixture directory, the specs silently pass.
  That is acceptable for local convenience but not enough for CI parity.

## P0: Resolve Remaining Contract Ambiguity

1. Reconcile `obsctl status` semantics.
   - Decide whether `status` is an OBS-only alias for `obs-status`, or the
     combined server-and-OBS status promised by the acceptance plan.
   - If it remains OBS-only, update `TODO.md`, `IMPLEMENTATION_CHECK_PLAN.md`,
     README, command docs, and fixture names/comments to make that deliberate.
   - If it should be combined, add a server command/result shape that includes
     daemon status and OBS snapshot data, then update human/JSON golden
     fixtures.

2. Strengthen cross-project contract compatibility.
   - When `../obsctl-rs` exists, fail with a clear message if no recognized
     fixture root exists unless an explicit skip env var is set.
   - Compare fixture sets in both directions, not only local files against
     sibling files, so missing sibling/local fixtures are visible.
   - Add this compatibility mode to CI only when both repositories are checked
     out.

## P0: Finish Reconnect Observability

1. Preserve protocol-error root cause through supervisor state.
   - Expose the low-level OBS client terminal error to `ObsSupervisor` instead
     of reducing every post-identify failure to `"OBS WebSocket closed"`.
   - Ensure `server-status.last_error`, state events, and logs distinguish
     clean close, passive disconnect, malformed OBS frame, and response parser
     error.
   - Keep public messages secret-free.

2. Make server reconnect status honest.
   - Track reconnecting state directly instead of deriving it only from
     disconnected plus reconnect-enabled.
   - Include `last_connected_at`, `last_disconnected_at`, and
     `last_reconnect_attempt_at` in server status.
   - Add golden JSON/human fixture updates for the expanded status payload.

3. Remove remaining fixed sleeps from reconnect/pending-request specs.
   - Extend fake OBS probes for reconnect attempt, close acknowledgement, and
     delayed response completion.
   - Replace `sleep` polling where a channel/probe can prove the transition.

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

## P2: Test Infrastructure

1. Add CI.
   - `crystal tool format --check`
   - `crystal spec`
   - `ameba` when installed
   - release build
   - optional dual-repo fixture compatibility

2. Strengthen fake OBS coverage.
   - out-of-order responses
   - dropped connection
   - passive close
   - OBS request failures
   - structural scene/input events

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

1. Resolve `obsctl status` semantics and update fixtures/docs accordingly.
2. Preserve OBS protocol-error root causes in supervisor state/logs, then add
   honest reconnect timestamps to `server-status`.
3. Harden optional `../obsctl-rs` fixture compatibility for dual-repo CI.

## Build Gates

For every Crystal change:

```sh
make format
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build
make lint
```
