# Final Implementation-Check Plan

This is the strict implementation and review plan for `obsctl-cr`. It assumes the corrected architecture: one long-running local server owns the OBS WebSocket connection; TUI and CLI are clients/proxies over local IPC.

## Project

- Name: `obsctl-cr`
- Language: Crystal 1.20.2
- Primary goal: build a local OBS control daemon with CLI and TUI clients.

Core architecture:

```text
OBS Studio <---- obs-websocket 5.x ----> obsctl server <---- Unix socket IPC ----> obsctl TUI
                                                               <---- Unix socket IPC ----> obsctl CLI
```

Hard rule:

- Exactly one process owns the OBS WebSocket connection: `obsctl server`.
- CLI and TUI must not connect directly to OBS in normal mode.
- CLI and TUI must connect to the local obsctl server and send commands through IPC.

## Runtime Modes

- `obsctl server`: foreground local server.
- `obsctl server --headless`: server without UI, intended for `systemd --user`.
- `obsctl`: TUI client that connects to local server and shows a server-unavailable screen if needed.
- `obsctl tui`: explicit TUI client mode.
- `obsctl scene <target>`: CLI client command through server.
- `obsctl mute <target>`: CLI client command through server.
- `obsctl unmute <target>`: CLI client command through server.
- `obsctl toggle-mute <target>`: CLI client command through server.
- `obsctl vol <target> <0-100>`: CLI client command through server.
- `obsctl status`: asks local server for server and OBS status.
- `obsctl dump-config`: asks server to fetch OBS state and merge into config.
- `obsctl reload-config`: asks server to reload config and rebroadcast state.
- `obsctl service install/start/stop/restart/status/uninstall`: manages `systemd --user` service.

Implementation stack:

- Crystal stdlib `OptionParser` for outer CLI.
- Unix domain sockets for local IPC.
- Newline-delimited JSON over Unix socket.
- termisu for TUI.
- YAML config.
- Crystal fibers/channels for concurrency.
- Optional Ameba for linting.

Do not add a heavy command framework unless `OptionParser` becomes insufficient.

## Required Module Layout

```text
src/
  obsctl.cr
  obsctl/
    cli/
      main.cr
      options.cr
      command_router.cr
      client_commands.cr
    server/
      server.cr
      server_options.cr
      lifecycle.cr
      client_registry.cr
      command_executor.cr
      state_store.cr
      obs_supervisor.cr
    ipc/
      socket_path.cr
      unix_server.cr
      unix_client.cr
      protocol.cr
      request.cr
      response.cr
      event.cr
      codec.cr
      client_session.cr
    config/
    obs/
    domain/
    tui/
    service/
      systemd_user_service.cr
      service_installer.cr
    runtime/
      reconnect_policy.cr
      logger.cr
      signal_handler.cr
      scheduler.cr
    support/
```

Specs must mirror major areas under `spec/obsctl/{cli,server,ipc,config,obs,domain,tui,service}`.

## OBS WebSocket Requirements

Target protocol: obs-websocket 5.x.

Connection flow:

1. Connect WebSocket.
2. Receive Hello, opcode `0`.
3. Send Identify, opcode `1`.
4. Receive Identified, opcode `2`.
5. Only after Identified, send Request messages, opcode `6`.
6. Handle RequestResponse messages, opcode `7`.
7. Handle Event messages, opcode `5`.

Authentication:

- password + salt
- SHA256
- Base64
- base64_secret + challenge
- SHA256
- Base64

Security:

- Never log password.
- Never log generated authentication string.
- Redact sensitive config fields.
- Prefer `password_env` over plaintext password.

Required OBS requests:

- Version: `GetVersion`
- Scenes: `GetSceneList`, `GetCurrentProgramScene`, `SetCurrentProgramScene`
- Audio: `GetInputList`, `GetInputMute`, `SetInputMute`, `ToggleInputMute`, `GetInputVolume`, `SetInputVolume`

Required OBS events:

- current program scene changed
- scene list changed
- input mute state changed
- input volume changed, if available
- connection closed/failure handled by supervisor

OBS client requirements:

- typed request wrappers
- request ID generator
- pending request map
- timeout handling
- response matching by `requestId`
- event dispatch
- graceful close
- reconnect-safe state reset

## Server Requirements

The server owns:

- OBS WebSocket connection
- OBS authentication
- reconnect loop
- authoritative OBS state cache
- config loading and validation
- alias/shortcut resolution
- command execution
- dump-config logic
- local IPC socket
- client session registry
- state/event/log broadcasting

Startup:

1. Resolve config path.
2. Load config.
3. Validate config.
4. Resolve socket path.
5. Create runtime directory.
6. Check for existing active socket.
7. Remove stale socket if no process responds.
8. Start IPC accept loop.
9. Start OBS supervisor.
10. Attempt OBS connection.
11. Authenticate.
12. Fetch initial snapshot.
13. Broadcast state to subscribed clients.
14. Continue until SIGINT/SIGTERM.

Shutdown:

- stop accepting clients
- close IPC client sessions
- close OBS WebSocket
- remove socket file
- flush logs

Socket path:

- Preferred: `$XDG_RUNTIME_DIR/obsctl/obsctl.sock`
- Fallback: `/tmp/obsctl-$UID/obsctl.sock`

IPC:

- Use Unix domain sockets.
- Do not use TCP by default.
- Do not expose remote control API over network.

Reconnect behavior:

- enabled by default
- endless by default in server mode
- exponential backoff
- max delay cap
- optional jitter
- reset backoff after successful connection
- server must stay alive when OBS is closed
- local IPC must continue working while OBS is disconnected

OBS unavailable behavior:

- status command still works
- TUI shows disconnected state
- scene/audio commands return `OBS_UNAVAILABLE`
- server keeps retrying

## IPC Protocol

Transport: newline-delimited JSON over Unix socket.

Request:

```json
{"id":"req-000001","type":"command","command":{"name":"set_scene","target":"main"}}
```

Success response:

```json
{"id":"req-000001","type":"response","ok":true,"result":{"message":"Scene changed to Main Camera"}}
```

Error response:

```json
{"id":"req-000002","type":"response","ok":false,"error":{"code":"SCENE_NOT_FOUND","message":"Scene alias not found: cam"}}
```

Subscribe request:

```json
{"id":"req-000003","type":"subscribe","topics":["state","events","logs"]}
```

Pushed event:

```json
{"type":"event","topic":"state","data":{"connected":true,"current_scene":"Main Camera","scenes":[],"audio_inputs":[]}}
```

Required IPC commands:

- `Ping`
- `GetServerStatus`
- `GetObsStatus`
- `GetSnapshot`
- `Subscribe`
- `SetScene(target)`
- `Mute(target)`
- `Unmute(target)`
- `ToggleMute(target)`
- `SetVolume(target, percent)`
- `DumpConfig`
- `ReloadConfig`
- `ValidateConfig`
- `ReconnectObs`
- `ShutdownServer`

`ShutdownServer` is disabled by default and requires:

```yaml
server:
  allow_remote_shutdown: true
```

Even though IPC is local, treat commands as external input.

## Config Requirements

Default path: `~/.config/obsctl/config.yml`.

Environment override: `OBSCTL_CONFIG=/path/to/config.yml`.

Target config shape:

```yaml
version: 1

server:
  socket_path: null
  pid_file: null
  allow_remote_shutdown: false
  start_embedded_if_missing: true

connection:
  host: "127.0.0.1"
  port: 4455
  password_env: "OBS_WEBSOCKET_PASSWORD"
  connect_timeout_ms: 3000
  request_timeout_ms: 2500

reconnect:
  enabled: true
  endless: true
  initial_delay_ms: 500
  max_delay_ms: 10000
  multiplier: 1.8
  jitter_ms: 250
```

Validation:

- valid version
- valid host
- valid port
- valid timeout values
- valid reconnect values
- valid UI refresh interval
- `password_env` exists if configured
- no duplicate scene aliases
- no duplicate scene shortcuts
- no duplicate audio aliases
- no duplicate audio shortcuts
- no ambiguous alias/shortcut collisions

Alias resolution order:

1. exact shortcut
2. exact alias
3. exact OBS object name
4. case-insensitive alias
5. case-insensitive OBS object name

Ambiguous target returns explicit error and does not execute.

## Dump Config Requirements

`obsctl dump-config` and `/dump-config` are server-performed operations. CLI/TUI only send requests.

Behavior:

1. Server connects to OBS or uses active connection.
2. Fetch current scenes.
3. Fetch current audio inputs.
4. Read existing config.
5. Preserve aliases, shortcuts, groups, and user edits.
6. Add missing OBS scenes/audio inputs.
7. Mark missing/stale OBS objects instead of deleting them, if implemented.
8. Create `config.yml.bak.<timestamp>`.
9. Write atomically.

Must not:

- silently erase user aliases
- overwrite without backup
- expose password

## TUI Requirements

TUI is a client.

Startup:

1. Resolve local socket path.
2. Connect to obsctl server.
3. If connected, subscribe to state/events/logs and render dashboard.
4. If not connected, show server-unavailable screen with:
   - start embedded server
   - start headless server
   - show service install command
   - retry
   - quit

TUI must not duplicate OBS WebSocket client logic.

Dashboard style: inspired by btop/btm.

Panels:

- Header: app name, server status, OBS status, OBS Studio version, obs-websocket version
- Scenes panel: scene list, active highlight, alias, shortcut, group
- Scene map panel: grouped textual map, current scene clear
- Audio panel: input/output name, alias, shortcut, mute state, volume percent
- Bottom command palette: input line, last command result, compact error/log area

Command palette:

- `/help`
- `/scene <target>`
- `/set-scene <target>`
- `/mute <target>`
- `/unmute <target>`
- `/toggle-mute <target>`
- `/vol <target> <0-100>`
- `/status`
- `/server-status`
- `/obs-status`
- `/reconnect`
- `/dump-config`
- `/reload-config`
- `/quit`

Parser:

- typed command parser
- quoted names
- argument count validation
- volume range validation
- structured errors

## CLI Client Requirements

CLI commands are thin proxy calls.

Flow:

1. Parse shell args.
2. Resolve socket path.
3. Connect to local obsctl server.
4. If unavailable, print:

```text
obsctl server is not running.
Start it with:
  obsctl server --headless
Or install service:
  obsctl service install
  systemctl --user enable --now obsctl.service
```

5. Exit `3` when server is unavailable.
6. Send IPC command.
7. Wait for response.
8. Print concise output.
9. Exit with mapped code.

Do not silently start server from non-interactive CLI commands unless explicitly configured.

Exit codes:

- `0` success
- `1` generic failure
- `2` config error
- `3` server/connection/auth error
- `4` OBS request error
- `5` command parse error
- `6` IPC error

## Systemd User Service

Commands:

- `obsctl service install`
- `obsctl service uninstall`
- `obsctl service status`
- `obsctl service start`
- `obsctl service stop`
- `obsctl service restart`

Install path: `~/.config/systemd/user/obsctl.service`.

Template:

```ini
[Unit]
Description=obsctl OBS WebSocket control daemon
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=<absolute-path-to-obsctl> server --headless
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
```

Rules:

- no sudo
- use `systemd --user`
- detect actual executable path
- do not hardcode `~/.local/bin/obsctl`
- run `systemctl --user daemon-reload` after install

## State Model

`ObsSnapshot`:

- `connected : Bool`
- `obs_studio_version : String?`
- `obs_websocket_version : String?`
- `current_scene : String?`
- `scenes : Array(SceneState)`
- `audio_inputs : Array(AudioState)`
- `last_error : String?`
- `updated_at : Time`

`SceneState`:

- `name : String`
- `alias : String?`
- `shortcut : String?`
- `group : String?`
- `active : Bool`

`AudioState`:

- `name : String`
- `alias : String?`
- `shortcut : String?`
- `kind : String?`
- `muted : Bool?`
- `volume_mul : Float64?`
- `volume_db : Float64?`
- `volume_percent : Int32?`

`ServerStatus`:

- `pid : Int32`
- `uptime_seconds : Int64`
- `socket_path : String`
- `client_count : Int32`
- `obs_connected : Bool`
- `reconnecting : Bool`
- `last_error : String?`

State rules:

- server has authoritative state
- TUI only renders received state
- CLI receives snapshots/responses only
- OBS events update `StateStore`
- `StateStore` broadcasts updates to subscribers

## Volume

- User-facing volume is 0-100 percent.
- Internal initial mapping: `percent / 100.0`.
- Validate range `0..100`.
- Isolate conversion in one module.
- Keep dB support optional/future.

## Concurrency

Use Crystal fibers/channels.

Separate:

- IPC accept loop
- IPC client session fibers
- OBS supervisor fiber
- OBS WebSocket reader fiber
- OBS request coordinator
- TUI event loop
- TUI renderer
- command executor

Avoid:

- shared mutable global state
- blocking network operations in renderer
- OBS requests directly from UI widgets
- duplicated WebSocket connections

## Errors

Define typed/domain errors:

- `ConfigNotFound`
- `ConfigInvalid`
- `ServerUnavailable`
- `IpcConnectionFailed`
- `ConnectionFailed`
- `AuthenticationFailed`
- `ObsUnavailable`
- `RequestTimeout`
- `ObsRequestFailed`
- `SceneNotFound`
- `AudioInputNotFound`
- `AliasAmbiguous`
- `CommandParseError`
- `DumpConfigFailed`
- `ServiceInstallFailed`

Messages must be concise, actionable, safe, and secret-free.

## Logging

Default path: `~/.local/state/obsctl/obsctl.log`.

CLI option: `--log-level debug|info|warn|error`.

Rules:

- debug may include request type and request ID
- never log password
- never log auth token/string
- TUI shows compact recent errors only

## Testing Requirements

Unit tests:

- config load/validation/write
- alias resolution
- command parser and quoted command parsing
- volume conversion
- IPC codec encode/decode
- IPC response correlation
- OBS auth hash generation
- OBS request serialization
- OBS response matching
- dump-config merge behavior
- stale socket detection
- systemd service generation

Integration tests:

- fake OBS WebSocket server
- fake IPC client
- server starts and exposes socket
- CLI command reaches server
- server sends OBS request
- OBS response returns to CLI
- TUI subscription receives state snapshot
- OBS disconnect does not kill server
- server reconnects after fake OBS returns

Quality gates:

- `crystal spec` passes
- `crystal tool format` passes
- Ameba passes if added
- no avoidable compiler warnings

## Implementation Milestones

1. Project skeleton
2. Config
3. IPC
4. Server core
5. OBS client
6. Scene control through server
7. Audio control through server
8. Reconnect supervisor
9. Dump config through server
10. TUI MVP as server client
11. Systemd user service
12. Polish, docs, troubleshooting, packaging

## Final Acceptance Checklist

Server:

- [ ] `obsctl server` starts in foreground.
- [ ] `obsctl server --headless` starts without TUI.
- [ ] Server creates Unix socket.
- [ ] Server rejects active duplicate server.
- [ ] Server removes stale socket.
- [ ] Server connects to OBS.
- [ ] Server authenticates with OBS.
- [ ] Server fetches initial OBS snapshot.
- [ ] Server survives OBS being closed.
- [ ] Server reconnects endlessly.
- [ ] Server keeps IPC alive while OBS is disconnected.
- [ ] Server shuts down cleanly on SIGINT/SIGTERM.

CLI:

- [ ] `obsctl status` talks to local server.
- [ ] `obsctl scene 1` changes scene through server.
- [ ] `obsctl scene main` changes scene through server.
- [ ] `obsctl mute mic` works through server.
- [ ] `obsctl unmute mic` works through server.
- [ ] `obsctl toggle-mute mic` works through server.
- [ ] `obsctl vol mic 70` works through server.
- [ ] CLI exits non-zero when server is unavailable.
- [ ] CLI does not connect directly to OBS.

TUI:

- [ ] `obsctl` starts TUI client.
- [ ] TUI connects to local server.
- [ ] TUI shows server status.
- [ ] TUI shows OBS connection status.
- [ ] TUI shows current scene.
- [ ] TUI shows scene list/map.
- [ ] TUI shows audio inputs/outputs.
- [ ] TUI command `/scene 1` works.
- [ ] TUI command `/mute mic` works.
- [ ] Closing TUI does not stop server.

Config:

- [ ] `obsctl init` creates config.
- [ ] `obsctl validate-config` validates config.
- [ ] `obsctl dump-config` writes current OBS data.
- [ ] dump-config preserves aliases.
- [ ] dump-config creates backup.
- [ ] config password is not logged.
- [ ] `password_env` is supported.

Systemd:

- [ ] `obsctl service install` writes user service.
- [ ] service uses absolute obsctl path.
- [ ] `systemctl --user enable --now obsctl.service` works.
- [ ] service restarts on crash.
- [ ] service runs without sudo.

Protocol:

- [ ] OBS requests are sent only after Identified.
- [ ] `requestId` correlation works.
- [ ] timeouts work.
- [ ] OBS errors map to domain errors.
- [ ] IPC errors map to CLI exit codes.

Security:

- [ ] no password in logs.
- [ ] no auth string in logs.
- [ ] Unix socket permissions are local-user safe.
- [ ] remote TCP control is not enabled by default.

Code quality:

- [ ] no OBS logic in TUI renderer.
- [ ] no OBS logic in CLI client.
- [ ] command parsing is typed.
- [ ] alias resolution is centralized.
- [ ] volume conversion is centralized.
- [ ] state ownership is server-side.
- [ ] specs pass.
- [ ] formatting passes.

## Non-Goals For First Implementation

Do not implement initially:

- TCP remote API
- multi-user daemon
- plugin system
- complex scene graph editing
- OBS source visibility control
- stream/record controls
- audio level meters
- custom scripting language
- daemonization without systemd
- encrypted config store

Final invariant:

```text
The server is the brain.
The TUI is a live dashboard.
The CLI is a thin command proxy.
OBS is never controlled directly by multiple obsctl processes.
```
