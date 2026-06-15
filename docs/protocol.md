# Protocol Notes

## Local IPC

`obsctl` local client/server traffic uses Unix domain sockets with newline-delimited JSON. The default socket path is `$XDG_RUNTIME_DIR/obsctl/obsctl.sock`; when `XDG_RUNTIME_DIR` is unavailable, it falls back to `/tmp/obsctl-$UID/obsctl.sock`.

Each frame is one JSON object followed by `\n`.

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
