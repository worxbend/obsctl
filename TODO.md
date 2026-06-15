# obsctl-cr Implementation Tracker

This tracker is grounded in the initial project brief. It records what is implemented, what is partial, what remains, and the next planned work.

## Major Architecture Update: Local Client/Server

`obsctl-cr` must evolve from a direct CLI/TUI-to-OBS application into a local client/server application.

Core process model:

```text
OBS Studio <----obs-websocket----> obsctl server <----local IPC----> obsctl TUI
                                                    <----local IPC----> obsctl CLI
```

Critical rule:

- There must be exactly one OBS WebSocket owner per user session: the `obsctl server`.
- CLI and TUI clients must not create their own OBS WebSocket connection in normal mode.
- Direct OBS access is allowed only inside server mode or explicit embedded-server mode.

### Runtime Modes

Server mode:

- `obsctl server`
- Runs a long-lived local daemon process.
- Connects to OBS WebSocket.
- Maintains authoritative OBS state.
- Reconnects forever when enabled.
- Accepts local client commands from CLI/TUI sessions.
- Can run headlessly as a `systemd --user` service.

TUI mode:

- `obsctl`
- `obsctl tui`
- Starts an interactive TUI client.
- Connects to the local `obsctl server`.
- If no server is running, shows a server-unavailable screen with options:
  - start embedded server
  - start headless server
  - show service install command
  - generate config
  - retry
  - quit
- The TUI does not talk directly to OBS unless explicitly running in embedded/server mode.

CLI client mode:

- `obsctl scene main`
- `obsctl mute mic`
- `obsctl vol mic 70`
- `obsctl status`
- Parses shell arguments, connects to local IPC, sends a command, prints the response, and exits.
- Does not silently start the server unless explicitly configured, because implicit daemon startup is surprising for scripts.

### Updated Command Behavior

- `obsctl`: starts TUI client.
- `obsctl tui`: starts TUI client.
- `obsctl server`: starts foreground server, useful for debugging.
- `obsctl server --headless`: starts foreground headless server for systemd service execution.
- `obsctl server --daemon`: optional later; prefer systemd user services.
- `obsctl status`: sends status request to local server.
- `obsctl server-status`: checks only the local obsctl server, not OBS.
- `obsctl scene <alias|shortcut|obs-name>`: sends scene-change request to server.
- `obsctl mute <audio-target>`: sends mute request to server.
- `obsctl unmute <audio-target>`: sends unmute request to server.
- `obsctl toggle-mute <audio-target>`: sends toggle mute request to server.
- `obsctl vol <audio-target> <0-100>`: sends volume request to server.
- `obsctl dump-config`: sends dump-config request to server; server reads OBS state and writes config.
- `obsctl reload-config`: sends reload-config request to server.

### Local IPC

Primary transport:

- Unix domain socket.
- Default socket path: `$XDG_RUNTIME_DIR/obsctl/obsctl.sock`.
- Fallback socket path: `/tmp/obsctl-$UID/obsctl.sock`.
- Do not use TCP for local IPC by default.

Reasons:

- lower overhead
- safer local-only access
- systemd user service friendly
- simple permission model
- avoids exposing the control API over the network

Protocol:

- Newline-delimited JSON over Unix socket.
- One JSON object per line.

Client command request:

```json
{"id":"req-000001","type":"command","command":{"name":"set_scene","target":"main"}}
```

Server success response:

```json
{"id":"req-000001","type":"response","ok":true,"result":{"message":"Scene changed to Main Camera"}}
```

Server error response:

```json
{"id":"req-000002","type":"response","ok":false,"error":{"code":"SCENE_NOT_FOUND","message":"Scene alias not found: cam"}}
```

TUI subscription request:

```json
{"id":"req-000003","type":"subscribe","topics":["state","events","logs"]}
```

Pushed state event:

```json
{"type":"event","topic":"state","data":{"connected":true,"current_scene":"Main Camera","scenes":[],"audio_inputs":[]}}
```

### Server Responsibilities

The server is the only process that owns:

- OBS WebSocket connection
- OBS authentication
- reconnect loop
- authoritative OBS state cache
- config loading and validation
- alias resolution
- command execution
- dump-config logic
- OBS event subscription
- local IPC socket
- client session registry

The CLI and TUI are thin clients.

CLI client responsibilities:

- parse shell arguments
- resolve Unix socket path
- connect to local server
- send typed command
- print response
- exit with mapped exit code
- if server is missing, print startup/service instructions and exit `3`

TUI client responsibilities:

- connect to Unix socket
- subscribe to state/events/logs
- render dashboard
- parse command palette input
- send commands to server
- render command responses

### Updated Module Layout Target

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
      systemd.cr
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
    support/
```

### Server Lifecycle

Startup:

1. Resolve config path.
2. Load config.
3. Validate config.
4. Create runtime directory, usually `$XDG_RUNTIME_DIR/obsctl`.
5. Create Unix socket, usually `$XDG_RUNTIME_DIR/obsctl/obsctl.sock`.
6. Refuse to start if another server responds on the socket.
7. Remove stale socket if no process is listening.
8. Start IPC accept loop.
9. Start OBS supervisor.
10. Connect to OBS.
11. Authenticate.
12. Fetch initial snapshot.
13. Broadcast state to subscribed clients.
14. Continue until SIGINT/SIGTERM.

Shutdown:

- stop accepting IPC clients
- close client sessions
- close OBS WebSocket
- remove socket file
- flush logs

### OBS Supervisor

Implement an `ObsSupervisor` fiber.

Responsibilities:

- maintain connection state
- reconnect endlessly when enabled
- expose current state snapshot
- serialize OBS requests
- process OBS events
- broadcast state changes to IPC subscribers

Reconnect behavior:

- enabled by default in server mode
- endless retry
- exponential backoff with max delay
- optional jitter
- reset backoff after successful connection
- never crash server because OBS is closed
- keep local IPC available when OBS is unavailable

State when OBS is down:

- server remains alive
- TUI shows OBS disconnected
- CLI commands fail with `OBS_UNAVAILABLE`
- status still works
- server keeps retrying

### IPC Command Model

Define typed IPC commands:

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
- `ShutdownServer`

`ShutdownServer` must be disabled by default or require explicit config:

```yaml
server:
  allow_remote_shutdown: false
```

Even though IPC is local, treat commands as external input and validate everything.

### Systemd User Service

Add commands:

- `obsctl service install`
- `obsctl service uninstall`
- `obsctl service status`
- `obsctl service start`
- `obsctl service stop`
- `obsctl service restart`

Install writes:

```text
~/.config/systemd/user/obsctl.service
```

Service template:

```ini
[Unit]
Description=obsctl OBS WebSocket control daemon
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=/absolute/path/to/obsctl server --headless
Restart=always
RestartSec=3
Environment=RUST_BACKTRACE=0

[Install]
WantedBy=default.target
```

Rules:

- Detect the current executable path for `ExecStart`.
- Prefer absolute path.
- Do not hardcode `%h/.local/bin` if the binary is elsewhere.
- Run `systemctl --user daemon-reload` after writing the service.
- Do not require `sudo`; this is a user service.

### Config Additions Target

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

Current config still has reconnect nested under `connection`; migration or compatibility handling is required.

### Headless Server Acceptance Criteria

Headless server must:

- run without TUI
- run under `systemd --user`
- keep IPC socket alive
- connect to OBS when OBS becomes available
- reconnect endlessly after OBS restart
- keep serving local CLI/TUI clients while OBS is disconnected
- expose meaningful status
- never leak password/auth data
- clean stale socket on startup

Given `obsctl server --headless` is running:

- `obsctl status` returns server and OBS status.
- `obsctl scene main` changes scene through the server.
- `obsctl mute mic` mutes through the server.
- `obsctl tui` attaches to the already-running server.
- closing TUI does not stop the server.
- restarting OBS does not kill the server.
- server reconnects when OBS returns.
- dump-config is performed by the server, not by the CLI client.

## Current Status

Implemented:

- Crystal project skeleton targeting Crystal `>= 1.20.2`.
- `bin/obsctl` build target through `shard.yml` and `Makefile`.
- Layered source layout under `src/obsctl`.
- CLI entrypoint using Crystal stdlib `OptionParser`.
- Scriptable commands:
  - `obsctl init`
  - `obsctl validate-config`
  - `obsctl dump-config`
  - `obsctl reload-config`
  - `obsctl scene <target>`
  - `obsctl mute <target>`
  - `obsctl unmute <target>`
  - `obsctl toggle-mute <target>`
  - `obsctl volume <target> <0-100>`
  - `obsctl vol <target> <0-100>`
  - `obsctl status`
  - `obsctl server-status`
  - non-interactive OBS control commands are thin IPC clients and return exit `3` with startup/service instructions when the local server is missing
- Command palette parser for:
  - `/help`
  - `/set-scene <target>`
  - `/scene <target>`
  - `/mute <target>`
  - `/unmute <target>`
  - `/toggle-mute <target>`
  - `/vol <target> <0-100>`
  - `/dump-config`
  - `/reload-config`
  - `/status`
  - `/connect`
  - `/disconnect`
  - `/quit`
- Quoted command arguments, for example `/scene "Main Camera"`.
- Typed command structs and command parse errors.
- Config path resolution:
  - default Linux path `~/.config/obsctl/config.yml`
  - `OBSCTL_CONFIG`
  - `--config PATH`
- YAML config load/write for known fields.
- Config validation:
  - unsupported version
  - invalid host
  - invalid port
  - missing configured password env var
  - invalid UI refresh interval
  - duplicate scene aliases
  - duplicate scene shortcuts
  - duplicate audio aliases
  - duplicate audio shortcuts
- Non-destructive config writes:
  - atomic write through temp file and rename
  - backup before overwriting existing config files
  - `init` refuses to overwrite unless `--force` is passed
- Dump config merge:
  - preserves existing aliases/shortcuts/groups
  - adds missing OBS scenes/audio inputs
  - marks removed OBS objects as `stale: true`
  - backs up existing config before writing
  - can bootstrap a missing config file before connecting
- Alias/shortcut lookup priority:
  - exact shortcut
  - exact alias
  - exact OBS name
  - case-insensitive alias
  - case-insensitive OBS name
  - ambiguous matches fail without executing action
- OBS authentication helper for obs-websocket 5.x password/salt/challenge flow.
- OBS protocol request serialization for opcode `6`.
- OBS protocol response parsing for opcode `7`.
- OBS event parsing for opcode `5`.
- OBS client request coordination:
  - per-request pending response channels keyed by `requestId`
  - unmatched responses are no longer consumed by unrelated requests
  - OBS events are routed to an event channel
- OBS client connection flow:
  - connect WebSocket
  - read Hello opcode `0`
  - send Identify opcode `1`
  - wait for Identified opcode `2`
  - prevent requests before identified
- OBS client operations:
  - `GetVersion`
  - `GetSceneList`
  - `GetCurrentProgramScene`
  - `SetCurrentProgramScene`
  - `GetInputList`
  - `GetInputMute`
  - `SetInputMute`
  - `ToggleInputMute`
  - `GetInputVolume`
  - `SetInputVolume`
- Snapshot model:
  - connection status
  - OBS Studio version
  - obs-websocket version
  - current scene
  - scene list with alias/shortcut/group/active flag
  - audio list with alias/shortcut/mute/volume state
  - timestamp and last error field
- Local IPC primitives:
  - typed command requests, subscribe requests, responses, errors, and events
  - newline-delimited JSON codec
  - Unix socket path resolution using `$XDG_RUNTIME_DIR/obsctl/obsctl.sock`
  - fallback Unix socket path `/tmp/obsctl-$UID/obsctl.sock`
  - Unix client, Unix server, and client session wrappers
  - stale socket cleanup before server bind
  - active socket detection before server bind
  - socket mode tightened to `0600`
- Server runtime scaffold:
  - `obsctl server`
  - `obsctl server --headless`
  - foreground Unix socket IPC accept loop
  - authoritative state store with disconnected snapshot
  - OBS supervisor fiber that owns the OBS WebSocket client
  - command executor for status/snapshot, scene/audio commands, dump-config, and reload-config
  - subscription acknowledgement with an initial state event
  - persistent client registry for subscribed IPC sessions
  - state snapshot broadcast fanout after server-side OBS state changes
  - IPC remains available when OBS is unavailable
- CLI IPC proxying:
  - non-interactive `status`, `server-status`, `scene`, `mute`, `unmute`, `toggle-mute`, `vol`/`volume`, `dump-config`, and `reload-config` commands send typed IPC requests
  - CLI no longer creates an OBS WebSocket client for normal scriptable OBS-control commands
  - missing local server prints startup/service instructions and exits `3`
- Minimal ANSI TUI scaffold:
  - dashboard render
  - scenes panel output
  - audio panel output
  - command loop
  - palette commands routed through the same parser as CLI
  - basic first-run config creation when interactive config is missing
  - normal TUI sessions subscribe to server state over local IPC
  - TUI scene/audio commands are sent to the server over IPC
  - TUI `/reload-config` and `/dump-config` are server-performed IPC commands
  - snapshot refresh after scene/audio commands
  - timer-based event polling in the ANSI TUI loop
  - server-pushed state events update the displayed snapshot
  - direct OBS session adapter remains available for explicit embedded-style use/tests
  - reconnect attempts use the configured reconnect policy
- Runtime scaffolding:
  - logger with secret redaction
  - reconnect policy
  - scheduler
  - event loop placeholder
- Documentation:
  - `README.md`
  - `docs/config.md`
  - `docs/protocol.md`
  - `docs/commands.md`
- Specs currently covering:
  - config load/write
  - config validation
  - config writer backups
  - config dump merge
  - command parser
  - alias resolution
  - volume conversion
  - OBS auth hash generation
  - protocol request serialization
  - protocol response matching fields
  - scene/audio request payloads
  - CLI missing-config error path
  - fake OBS WebSocket integration server
  - OBS client snapshot integration
  - OBS scene/audio command integration
  - TUI session command refresh behavior
  - TUI event application behavior
  - TUI reconnect-on-poll behavior
  - TUI IPC subscription and command forwarding behavior
  - CLI scene/audio integration against fake OBS server
  - CLI scene/audio integration through the local server IPC path
  - CLI missing-server exit path for thin client commands
  - IPC codec validation
  - IPC socket path resolution
  - IPC Unix socket request/response round trip
  - stale IPC socket cleanup
  - server IPC startup while OBS is unavailable
  - server-owned OBS scene command through IPC
  - server state broadcasts to subscribed IPC clients

## Partial

- Server:
  - foreground/headless runtime exists
  - OBS supervisor owns the OBS WebSocket client
  - IPC command executor can control scene/audio and dump/reload config
  - reconnect loop is basic and does not yet process OBS disconnects after an established connection
  - subscription handling maintains a client registry and broadcasts state updates, but does not yet broadcast distinct OBS/log event topics
- CLI:
  - non-interactive OBS control commands are thin IPC clients
  - `server-status` exists with PID, connected state, last error, and subscribed client count
- TUI:
  - currently a simple ANSI dashboard and line-based command loop
  - normal mode subscribes to the local server over IPC instead of creating an OBS WebSocket connection
  - not yet a full termisu dashboard
  - not yet btop/btm-style keyboard-first layout
  - does not yet do raw-mode key handling
  - refreshes on a timer, but rendering is still full-screen ANSI redraw
- OBS client:
  - has a single WebSocket reader channel
  - has a pending request map for request/response coordination
  - event parsing exists and events are routed to a client channel
  - direct embedded-style TUI sessions can consume the event channel, but normal TUI mode consumes server-pushed IPC state
  - reconnect policy is still wired into the TUI session for server reconnects, but not into the low-level OBS client itself
- Config:
  - known fields round-trip
  - unknown top-level fields are explicitly rejected to avoid silent data loss
  - nested unknown fields are not preserved yet
  - plaintext `password` is supported by the data model but warning behavior is not yet surfaced
- Logging:
  - logger exists with redaction
  - CLI/TUI do not yet consistently use it
- First run:
  - missing interactive config creates a safe default
  - no guided host/port/password prompt yet
  - no optional connect-and-dump flow yet
- Tests:
  - CLI scene/audio fake-server specs exist, but dump-config CLI fake-server coverage is still missing
  - TUI session and IPC client specs exist, but no raw keyboard/input specs yet

## Not Yet Implemented

- Full termisu integration.
- Command palette UI with proper in-place editing.
- Keyboard shortcuts outside line-based command input.
- Scene map widget with grouped textual graph.
- Compact log panel with recent errors.
- Explicit OBS event subscription options during Identify.
- Low-level client reconnect loop independent of TUI session.
- Studio mode support.
- Stream/record controls and status.
- Scene item visibility controls.
- Volume meter events.
- Log level CLI behavior wired through runtime logger.
- `ameba` lint execution in this environment.
- Release packaging beyond `make release`.
- Public API/module documentation comments throughout.
- Unknown config field preservation.

## Milestone Tracking

### Milestone 1: CLI Skeleton

Done:

- shard project
- OptionParser
- config path resolution
- init command
- validate-config command
- specs

Remaining:

- improve init into a guided interactive setup
- add more CLI smoke tests

### Milestone 2: OBS WebSocket Client

Done:

- WebSocket connect
- Hello/Identify/Identified handshake
- obs-websocket 5.x auth helper
- GetVersion
- request timeout
- request ID generation
- pending response map keyed by request ID
- fake OBS WebSocket integration test server
- explicit event channel

Remaining:

- more robust close/error handling
- explicit event subscription options during Identify
- optional low-level client reconnect loop

### Milestone 3: Scene Control

Done:

- GetSceneList
- GetCurrentProgramScene
- SetCurrentProgramScene
- alias/shortcut resolution
- `obsctl scene <target>`

Remaining:

- add more CLI smoke tests for failure cases

### Milestone 4: Audio Control

Done:

- GetInputList
- GetInputMute
- SetInputMute
- ToggleInputMute
- GetInputVolume
- SetInputVolume
- `obsctl mute`
- `obsctl unmute`
- `obsctl toggle-mute`
- `obsctl volume`
- `obsctl vol`
- `obsctl status`
- CLI command execution through local server IPC

Remaining:

- improve volume display/formatting

### Milestone 5: Config Dump

Done:

- fetch scenes from OBS
- fetch inputs from OBS
- merge missing entries
- preserve aliases/shortcuts/groups
- mark stale removed entries
- backup before write
- atomic write
- bootstrap missing config path

Remaining:

- conflict reporting for duplicate aliases/shortcuts discovered during dump
- integration test against fake OBS server

### Milestone 6: TUI MVP

Partial:

- minimal dashboard
- command loop
- scene/audio display
- palette command parser reuse
- session-owned client adapter
- snapshot refresh after successful scene/audio commands
- `/reload-config`
- `/dump-config` with model refresh
- server state subscription over local IPC in normal mode
- scene/audio/dump/reload commands forwarded to the server in normal mode

Remaining:

- termisu app
- raw keyboard handling
- incremental/diff rendering instead of full-screen redraw
- proper layout panels
- command palette editing
- log panel

### Milestone 7: Realtime Events

Partial:

- scene changed events
- input mute changed events
- input volume changed events
- reconnect handling wired into runtime

### Milestone 8: Polish

Partial:

- README
- config docs
- protocol docs
- command docs
- Makefile

Remaining:

- better rendering
- theme file
- packaging
- demo config
- ameba lint wiring after dependency install
- public module documentation comments

### Milestone 9: Local IPC

Done:

- typed IPC request/response/event models
- newline-delimited JSON codec
- Unix socket path resolver
- Unix client/session wrappers
- Unix server primitive with stale socket cleanup and active socket detection
- IPC specs for codec, path resolution, and socket round trip
- server runtime integration with IPC accept loop
- initial server command execution over IPC
- non-interactive CLI command proxying through local IPC
- missing-server CLI exit behavior and startup/service instructions
- `server-status` command path
- persistent client registry and state broadcast fanout for subscriptions
- TUI IPC session client with subscription acknowledgement, initial state handling, command forwarding, and server-pushed state updates

Remaining:

- add event/log topic broadcast fanout after server-side producers exist
- harden request correlation helpers for long-lived clients if concurrent TUI requests are added later

## Planned Next

1. Add systemd user service install/uninstall/status/start/stop/restart support.
2. Add explicit OBS event subscription options during Identify in server mode.
3. Add dump-config CLI integration coverage through the server.
4. Improve close/error handling for pending requests and WebSocket shutdown.
5. Add raw-mode keyboard handling and a real command palette.
6. Evaluate/install `termisu` if available and replace ANSI rendering with proper widgets.
7. Add public documentation comments and run lint once dependencies are installed.
