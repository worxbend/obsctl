[product] obsctl-cr targets one OBS WebSocket owner per user session: `obsctl server`; normal CLI and TUI paths must use local Unix socket IPC.
[pattern] Thin CLI proxy commands map shell args to typed domain commands, then to `IPC::CommandPayload`, keeping OBS access server-side.
[pattern] Public IPC errors are centralized in `IPC::ErrorCode`; server and CLI code should use this taxonomy instead of ad hoc string codes.
[pattern] JSON CLI output is an envelope with `ok`, `result`, `error`, and `exit_code`; machine-readable stdout should stay separate from human diagnostics.
[pattern] Use fake local OBS/WebSocket servers and Unix socket fakes for integration specs; avoid live OBS dependencies.
[pattern] Crystal cache may need `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache` for reliable validation.
[learning] Regex architecture-boundary specs are useful but insufficient unless they scan every relevant layer and also protect require-level contracts.
[anti-pattern] Moving a class to fence architecture boundaries can silently break callers that relied on the old require path; document and test the new opt-in path.
[learning] OBS pending request cleanup must cover timeout, late response, concurrent response correlation, disconnect, and malformed frame paths.
[learning] Golden fixtures can freeze accidental behavior; reconcile command semantics against acceptance docs before treating fixtures as final contracts.
[learning] Protocol-error cleanup should preserve the root cause through supervisor state/logs, not only close the websocket and report a generic disconnect.
[anti-pattern] Optional cross-repo compatibility specs in the default suite can break local gates when a sibling checkout exists accidentally; strict dual-repo checks should be target-scoped or explicitly enabled.
[learning] A GitHub Actions sibling-repo compatibility job must checkout both repositories; checking for `../repo` after a single checkout only proves the job will skip.
[learning] Reconnect telemetry fields need precise transition semantics; `last_disconnected_at` should not be updated by connection attempts that never reached a connected state.
[learning] A strict cross-repo compatibility workflow should not be required until the counterpart repo has the expected fixture roots, or CI will be truthfully but unhelpfully red.
[learning] An explicit reconnect command must account for supervisor liveness; detaching an active client is insufficient when the reconnect loop has already exited.
[validation] Current full gates are `make format`, `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`, `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`, and `make lint`.
[security] Never log or expose OBS passwords, generated authentication strings, tokens, or secret-like values in IPC errors, JSON envelopes, logs, specs, or TUI output.
