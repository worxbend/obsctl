# obsctl Improvement Plan

This plan reflects the fresh reviewer pass on the June 20, 2026 contract-freeze
iteration. The daemon-first architecture is now substantially implemented and
the public contract work passes the current Crystal gates, but a few proof and
compatibility gaps remain before feature expansion is a good use of time.

## Current Assessment

`obsctl` is a serious local OBS controller with a daemon, Unix socket IPC, thin
CLI/TUI clients, service installation, config dump/validation, a fake OBS
server, and 140 passing Crystal specs.

The intended process model remains:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl CLI
                                                               <---- Unix socket IPC ----> obsctl TUI
```

Completed in the latest contract-freeze iteration:

- Proxy CLI commands support `--json` envelopes with `ok`, `result`, `error`,
  and `exit_code`.
- Public IPC error payloads are canonicalized through `IPC::ErrorCode`.
- Server command execution no longer emits vague public codes such as
  `CONFIG_ERROR`, `REQUEST_FAILED`, `INVALID_REQUEST`, or `INTERNAL_ERROR`.
- Normal CLI/TUI source has boundary specs against direct OBS client imports.
- The direct TUI OBS adapter was moved to an explicitly named
  `src/obsctl/tui/obs_session_client.cr` file.
- Golden fixtures now freeze representative CLI JSON/human output and one IPC
  command payload.
- Adversarial OBS request specs cover timeout cleanup, late responses,
  concurrent requests, disconnect during a request, and malformed OBS frames.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` with the existing Ameba-not-installed skip path

Reviewer findings:

- The architecture boundary specs are useful but incomplete: they do not scan
  `src/obsctl/ipc/**`, `src/obsctl/domain/**`, or `src/obsctl/support/**` for
  OBS implementation dependencies.
- Moving `TUI::ObsSessionClient` out of `session_client.cr` fenced the normal
  path, but it also changed the embedded/test require contract. A caller that
  only requires `src/obsctl/tui/session_client` no longer gets the adapter.
- Golden contract coverage is still representative, not comprehensive. It does
  not yet compare against `../obsctl-rs` and freezes only one IPC command
  payload.
- JSON mode mostly honors the stdout machine contract, but the project should
  explicitly decide whether JSON-mode warnings, especially
  `validate-config` warnings, may appear on stderr.
- OBS parser errors now clear pending requests, but the low-level client does
  not explicitly close the websocket on protocol error. The supervisor sees the
  client as disconnected, but the cleanup contract should be made explicit.

## P0: Close Contract-Freeze Gaps

1. Finish daemon-first boundary proof.
   - Extend architecture scans to `src/obsctl/ipc/**`, `src/obsctl/domain/**`,
     and `src/obsctl/support/**`.
   - Add a require-level spec for the embedded TUI adapter contract:
     either `require "./tui/obs_session_client"` is the documented opt-in path,
     or an explicit `obsctl tui --embedded` path is implemented.
   - Keep normal `obsctl`, `obsctl tui`, and CLI proxy paths unable to
     instantiate `OBS::Client`.

2. Expand golden CLI/IPC contracts.
   - Add fixtures for every current proxy command:
     `status`, `server-status`, `obs-status`, `scene`, `mute`, `unmute`,
     `toggle-mute`, `vol`, `dump-config`, `reload-config`, `reconnect`, and
     `shutdown-server`.
   - Freeze parse-error, server-unavailable, OBS-unavailable, config-invalid,
     timeout, and protocol-error envelopes.
   - Add optional compatibility checks against `../obsctl-rs` when the sibling
     repo is present.

3. Decide and enforce JSON diagnostics policy.
   - Choose one rule:
     - strict machine mode: JSON commands write no human text to stderr, or
     - stdout-only machine contract: one JSON object on stdout while warnings
       may still go to stderr.
   - Update docs and tests so `validate-config --json` follows the chosen rule.
   - Add tests for unsupported command plus `--json`, service/init plus
     `--json`, and invalid global options.

4. Make public error mapping exhaustive and auditable.
   - Add a table spec from domain errors to canonical IPC codes and CLI exit
     codes.
   - Revisit whether `ALIAS_AMBIGUOUS` should exit as command parse (`5`) or
     OBS request (`4`) and document the decision.
   - Improve redaction tests for quoted values, YAML-like `password: value`,
     and natural-language secret messages.

## P0: Finish Runtime Hardening

1. Make OBS protocol-error cleanup explicit.
   - Close the websocket after malformed OBS frames or route-response parser
     errors.
   - Prove the supervisor drops the client and reconnects after such protocol
     errors.
   - Keep pending request cleanup deterministic and nonblocking.

2. Replace remaining sleep-based spec synchronization.
   - Add fake OBS hooks for delayed-response completion and websocket close
     acknowledgement.
   - Prefer channels/probes over fixed sleeps in pending-request and server
     reconnect specs.

3. Make server status honest.
   - Track reconnecting state directly instead of deriving it only from
     disconnected plus reconnect-enabled.
   - Include `last_connected_at` and `last_reconnect_attempt_at` in server
     status.

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
   - server started/stopped
   - socket bound
   - OBS connected/disconnected
   - reconnect scheduled
   - config reloaded
   - command failed

3. Improve TUI log rendering.
   - Truncate long messages cleanly.
   - Preserve recent warning/error visibility.
   - Avoid allowing logs to dominate narrow terminal layouts.

## P2: Product Features

Add breadth only after the daemon/IPC contract is stable.

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

1. Strengthen fake OBS coverage.
   - out-of-order responses
   - dropped connection
   - passive close
   - OBS request failures
   - structural scene/input events

2. Add CI.
   - `crystal tool format --check`
   - `crystal spec`
   - `ameba` when installed
   - release build

3. Add optional compatibility tests against `../obsctl-rs`.
   - Skip when the sibling repo is absent.
   - Run in CI when both projects are checked out.

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

1. Complete contract-freeze proof: broader boundary scans, embedded adapter
   require contract, JSON diagnostics policy, and expanded fixtures.
2. Make OBS protocol-error cleanup explicit and remove sleep-based pending
   request specs.
3. Add honest reconnect status fields and server lifecycle timestamps.

## Build Gates

For every Crystal change:

```sh
make format
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build
make lint
```
