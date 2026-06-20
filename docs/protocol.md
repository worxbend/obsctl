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

Supported command names are `ping`, `get_server_status`, `get_obs_status`,
`get_snapshot`, `set_scene`, `mute`, `unmute`, `toggle_mute`, `set_volume`,
`dump_config`, `reload_config`, `validate_config`, `reconnect_obs`, and
`shutdown_server`. `shutdown_server` returns `SHUTDOWN_DISABLED` unless
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
printed to stdout in JSON mode; diagnostics and warnings, when present, stay on
stderr.

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
