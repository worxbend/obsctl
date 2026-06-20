[product] obsctl-cr targets one OBS WebSocket owner per user session: `obsctl server`; normal CLI and TUI paths must use local Unix socket IPC.
[pattern] Thin CLI proxy commands map shell args to typed domain commands, then to `IPC::CommandPayload`, keeping OBS access server-side.
[pattern] Public IPC errors are centralized in `IPC::ErrorCode`; server and CLI code should use this taxonomy instead of ad hoc string codes.
[pattern] JSON CLI output is an envelope with `ok`, `result`, `error`, and `exit_code`; machine-readable stdout should stay separate from human diagnostics.
[pattern] Use fake local OBS/WebSocket servers and Unix socket fakes for integration specs; avoid live OBS dependencies.
[pattern] Crystal cache may need `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache` for reliable validation.
[learning] Regex architecture-boundary specs are useful but insufficient unless they scan every relevant layer and also protect require-level contracts.
[anti-pattern] Moving a class to fence architecture boundaries can silently break callers that relied on the old require path; document and test the new opt-in path.
[learning] OBS pending request cleanup must cover timeout, late response, concurrent response correlation, disconnect, and malformed frame paths.
[validation] Current full gates are `make format`, `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`, `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`, and `make lint`.
[security] Never log or expose OBS passwords, generated authentication strings, tokens, or secret-like values in IPC errors, JSON envelopes, logs, specs, or TUI output.
