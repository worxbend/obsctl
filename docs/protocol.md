# Protocol Notes

## Local IPC

`obsctl` local client/server traffic uses Unix domain sockets with newline-delimited JSON. The default socket path is `$XDG_RUNTIME_DIR/obsctl/obsctl.sock`; when `XDG_RUNTIME_DIR` is unavailable, it falls back to `/tmp/obsctl-$UID/obsctl.sock`.

Each frame is one JSON object followed by `\n`.

The daemon-first boundary is part of the public contract. Normal CLI and TUI
paths talk to OBS only through the local IPC server. The only normal process
that owns an OBS WebSocket connection is `obsctl server`; embedded/direct OBS
adapters are explicitly fenced for tests or opt-in embedded use.

Command request:

```json
{"id":"req-000001","type":"command","command":{"name":"set_scene","target":"main"}}
```

Supported command names are `ping`, `status`, `get_server_status`,
`get_obs_status`, `get_snapshot`, `set_scene`, `mute`, `unmute`, `toggle_mute`,
`set_volume`, `dump_config`, `reload_config`, `validate_config`,
`reconnect_obs`, and `shutdown_server`. `status` returns the combined daemon
and OBS payload, `get_obs_status` returns only the OBS snapshot, and
`get_server_status` returns only daemon status. `shutdown_server` returns
`SHUTDOWN_DISABLED` unless
`server.allow_remote_shutdown` is enabled in the server config.

Subscribe request:

```json
{"id":"req-000002","type":"subscribe","topics":["state","events","logs"]}
```

The server validates subscription topics. Supported topics are `state`, `events`, and `logs`.
After a successful subscription, the server replies with an acknowledgement. Clients that
subscribe to `state` immediately receive the current snapshot. Later server-side snapshot
changes are broadcast as `state` events to state subscribers.

OBS events received by the server are broadcast on the `events` topic:

```json
{"type":"event","topic":"events","data":{"event_type":"CurrentProgramSceneChanged","event_data":{"sceneName":"BRB"}}}
```

Server log notifications are broadcast on the `logs` topic:

```json
{"type":"event","topic":"logs","data":{"level":"warn","code":"command_failed","message":"OBS is unavailable","created_at":"2026-06-15T18:00:00Z"}}
```

Success response:

```json
{"id":"req-000001","type":"response","ok":true,"result":{"message":"Scene changed to Main Camera"}}
```

Combined status response:

```json
{"id":"req-000004","type":"response","ok":true,"result":{"server":{"pid":4242,"uptime_seconds":37,"socket_path":"/tmp/obsctl/obsctl.sock","client_count":2,"obs_connected":true,"reconnecting":false,"last_connected_at":"2026-06-20T12:00:00Z","last_disconnected_at":null,"last_reconnect_attempt_at":"2026-06-20T11:59:59Z","last_connection_failed_at":null,"last_error":null,"dropped_reconnect_diagnostic_logs":0},"obs":{"connected":true,"current_scene":"Main Camera","scenes":[],"audio_inputs":[]}}}
```

Server status fields are the same in the combined `status` payload and the
daemon-only `get_server_status` payload. `last_disconnected_at` means OBS had
an established connected session and then disconnected. Initial connection
failures before any successful session leave it `null` and update
`last_connection_failed_at` instead. `last_connection_failed_at` is the most
recent failed OBS connection attempt, not necessarily the current disconnected
episode, and a later successful connection does not clear it. Only a newer
failed connection attempt replaces it. `last_reconnect_attempt_at` records when
the supervisor last started an OBS connection attempt.
`dropped_reconnect_diagnostic_logs` is an aggregate count of secondary
reconnect diagnostic `logs` topic messages dropped because the bounded
best-effort fanout was already at capacity. Runtime logging remains the durable
primary diagnostic sink; this field is telemetry for lossy subscriber fanout,
not per-drop log spam.

Explicit `reconnect_obs` requests return success only when the supervisor loop
is alive. Success means the running supervisor accepted a generation-scoped
reconnect request, or already has a prompt OBS connection attempt in progress;
it does not mean OBS is already connected. Accepted explicit requests are
durable across the next retry boundary, so a request made after a failed
connection attempt but before retry sleep starts is still acted on promptly. In
that case, `last_error` is set to `OBS reconnect requested`; the next connection
success or failure becomes the next public outcome. After the supervisor accepts
the request and any detached OBS client is closed, subscriber `state` and `logs`
fanout is best-effort. Publication failures are recorded as sanitized server
diagnostics and do not turn the accepted command into `SERVER_ERROR`.

```json
{"id":"req-000005","type":"response","ok":true,"result":{"message":"OBS reconnect requested"}}
```

If the supervisor has exited, for example because OBS was unavailable at startup
and `reconnect.enabled: false` was configured, `reconnect_obs` fails with a
public `OBS_UNAVAILABLE` error instead of reporting a requested reconnect.
Clients should treat the message as operator guidance and avoid assuming that a
new OBS connection attempt was scheduled:

```json
{"id":"req-000006","type":"response","ok":false,"error":{"code":"OBS_UNAVAILABLE","message":"OBS supervisor is not running; restart the server or enable reconnect."}}
```

Error response:

```json
{"id":"req-000003","type":"response","ok":false,"error":{"code":"OBS_UNAVAILABLE","message":"OBS is unavailable"}}
```

Pushed event:

```json
{"type":"event","topic":"state","data":{"connected":true,"current_scene":"Main Camera"}}
```

## Public IPC Error Codes

Server-to-client error responses use this canonical public error-code taxonomy:

- `CONFIG_INVALID`
- `SERVER_UNAVAILABLE`
- `OBS_UNAVAILABLE`
- `REQUEST_TIMEOUT`
- `OBS_REQUEST_FAILED`
- `SCENE_NOT_FOUND`
- `AUDIO_INPUT_NOT_FOUND`
- `ALIAS_AMBIGUOUS`
- `COMMAND_PARSE_ERROR`
- `IPC_PROTOCOL_ERROR`
- `SHUTDOWN_DISABLED`
- `SERVER_ERROR`

Public IPC responses must not expose secrets. Error messages are kept concise
and safe for CLI, TUI, and JSON consumers. Legacy vague boundary codes such as
`CONFIG_ERROR`, `REQUEST_FAILED`, `INTERNAL_ERROR`, and `INVALID_REQUEST` are
canonicalized before they are exposed to clients.

The CLI maps canonical IPC error codes to process exit codes with this public
contract:

| Error code | Exit code | Meaning |
| --- | ---: | --- |
| `CONFIG_INVALID` | 2 | Local or server config is invalid. |
| `SERVER_UNAVAILABLE` | 3 | The local obsctl server cannot be reached. |
| `OBS_UNAVAILABLE` | 3 | OBS is disconnected or unavailable. |
| `REQUEST_TIMEOUT` | 3 | OBS did not answer before the request timeout. |
| `OBS_REQUEST_FAILED` | 4 | OBS returned an unsuccessful request status. |
| `SCENE_NOT_FOUND` | 4 | A scene target could not be resolved. |
| `AUDIO_INPUT_NOT_FOUND` | 4 | An audio target could not be resolved. |
| `ALIAS_AMBIGUOUS` | 5 | A target matched multiple aliases/names before OBS was called. |
| `COMMAND_PARSE_ERROR` | 5 | CLI, TUI, or IPC command input was invalid. |
| `IPC_PROTOCOL_ERROR` | 6 | A local IPC frame was malformed or unexpected. |
| `SHUTDOWN_DISABLED` | 5 | Remote shutdown was rejected by command policy. |
| `SERVER_ERROR` | 1 | The server hit an internal failure. |

`ALIAS_AMBIGUOUS` intentionally exits as command parse error code `5`: the
requested target is ambiguous at obsctl's command/domain boundary, before any
OBS request is made.

## Shared Contract Fixtures

`obsctl` and `obsctl-rs` compare public contract fixtures only when the strict
dual-repo compatibility check is explicitly enabled. The default `make test`
gate does not require a sibling checkout and skips optional cross-repo
compatibility unless `OBSCTL_STRICT_OBSCTL_RS_COMPAT=1` is set.

The GitHub Actions strict compatibility workflow follows the same boundary: it
is a manual or scheduled signal, not an always-on push/pull-request gate while
the Rust repository lacks compatible fixtures. The workflow checks out this
repository as `obsctl`, checks out the selected Rust repository as `obsctl-rs`,
installs Crystal, and runs `make contract-rs-compat` from the Crystal checkout.
The Rust owner, repository name, and ref can come from workflow inputs or
repository variables.

Both repositories should expose the same shared fixture layout under one of
these recognized roots:

```text
spec/fixtures/contracts/
tests/fixtures/contracts/
fixtures/contracts/
```

The selected root must contain contract files in these subdirectories:

```text
<contract-root>/
  cli/
    human/
    json/
  ipc/
```

`cli/` stores frozen CLI output contracts, including human-readable output and
JSON envelopes. `ipc/` stores frozen newline-delimited JSON request payloads for
typed IPC commands. Strict compatibility compares matching fixture paths between
the two repositories, reports fixtures missing from either side, and reports
content differences after trimming surrounding whitespace.

Run the strict comparison from a prepared dual-repo workspace:

```sh
make contract-rs-compat
```

When strict mode is enabled, the check prints the selected sibling repository
path and the selected fixture root before comparing files. If no recognized
fixture root exists, the failure lists the expected roots and notes that the
root should contain `cli/` and `ipc/` fixture directories.

## CLI JSON Envelope

Thin CLI commands can request machine-readable output with `--json`. In JSON
mode, stdout contains exactly one JSON object:

```json
{"ok":true,"result":{"message":"Scene changed to Main Camera"},"error":null,"exit_code":0}
```

Failure envelopes keep the same shape and carry a canonical IPC error object:

```json
{"ok":false,"result":null,"error":{"code":"SCENE_NOT_FOUND","message":"scene not found: missing"},"exit_code":4}
```

Envelope fields are stable:

- `ok`: `true` for success, `false` for failure.
- `result`: the command payload or message on success; `null` on failure.
- `error`: `null` on success; `{code,message}` with a canonical public IPC
  code on failure.
- `exit_code`: the process exit code that the command returns.

JSON mode is intended for scripts. Startup hints and other human prose are not
printed to stdout in JSON mode. The stdout contract is exactly one
machine-readable JSON envelope. Secret-free human warnings, such as
`validate-config`'s plaintext-password warning, may still be written to stderr.
Using `--json` with a command that does not support JSON output returns a
`COMMAND_PARSE_ERROR` envelope and exit code `5` before command side effects.

## obs-websocket

The client follows obs-websocket 5.x ordering:

1. Connect WebSocket.
2. Read `Hello` opcode `0`.
3. Send `Identify` opcode `1`.
4. Wait for `Identified` opcode `2`.
5. Send `Request` opcode `6`.
6. Match `RequestResponse` opcode `7` by `requestId`.
7. Consume `Event` opcode `5` for realtime updates.

Server mode sends an explicit Identify `eventSubscriptions` mask for the OBS event categories it currently consumes: `General`, `Scenes`, and `Inputs`. High-volume events such as input volume meters are not subscribed by default.

Authentication uses `password + salt`, SHA256, Base64, then `base64_secret + challenge`, SHA256, Base64. Passwords and generated authentication strings must not be logged.
