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
[pattern] `obsctl reconnect` success should mean a live supervisor loop can act; stopped supervisors should return `OBS_UNAVAILABLE` instead of publishing requested state.
[learning] `last_connection_failed_at` is historical telemetry for the most recent failed OBS connection attempt and intentionally persists across later successful connections.
[pattern] Supervisor lifecycle checks must be generation-scoped; run loops, OBS client ownership, and reconnect wake signals should act only for the generation that created them.
[pattern] Explicit reconnect requests are generation-scoped durable epochs; active-client-close wakes are transient and must not leak into future retry delays.
[pattern] ReconnectSignal wait registration must stay atomic with the request-epoch check; durable explicit requests wake or skip retry sleeps without letting transient internal or cancel wakes advance the epoch.
[learning] Focused signal-level specs are the right boundary for reconnect wake races; supervisor fake-server specs should remain end-to-end witnesses, not the only proof of primitive synchronization.
[pattern] Deterministic fake-server probes are better than fixed sleeps for reconnect specs, but probe names must match what they observe, such as accepted WebSocket connections versus failed TCP attempts.
[learning] Remaining reconnect flake cleanup still includes replacing `unused_tcp_port` unavailable-then-bind windows and reducing `wait_for_disconnect` polling.
[validation] Current full gates are `make format`, `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`, `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`, and `make lint`.
[security] Never log or expose OBS passwords, generated authentication strings, tokens, or secret-like values in IPC errors, JSON envelopes, logs, specs, or TUI output.
