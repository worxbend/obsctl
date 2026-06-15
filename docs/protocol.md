# Protocol Notes

## Local IPC

`obsctl` local client/server traffic uses Unix domain sockets with newline-delimited JSON. The default socket path is `$XDG_RUNTIME_DIR/obsctl/obsctl.sock`; when `XDG_RUNTIME_DIR` is unavailable, it falls back to `/tmp/obsctl-$UID/obsctl.sock`.

Each frame is one JSON object followed by `\n`.

Command request:

```json
{"id":"req-000001","type":"command","command":{"name":"set_scene","target":"main"}}
```

Subscribe request:

```json
{"id":"req-000002","type":"subscribe","topics":["state","events","logs"]}
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

Authentication uses `password + salt`, SHA256, Base64, then `base64_secret + challenge`, SHA256, Base64. Passwords and generated authentication strings must not be logged.
