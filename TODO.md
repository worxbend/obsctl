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
- `obsctl status`: sends a combined daemon-and-OBS status request to the local server.
- `obsctl obs-status`: sends OBS status request to local server.
- `obsctl server-status`: checks only the local obsctl server, not OBS.
- `obsctl reconnect`: asks the server to reconnect its OBS WebSocket session;
  if the OBS supervisor is running, the command accepts a generation-scoped
  reconnect request or reports success because a prompt connection attempt is
  already in progress; if the supervisor is no longer running, the command
  returns `OBS_UNAVAILABLE` instead of claiming that a reconnect was requested.
- `obsctl shutdown-server`: asks the server to stop; disabled unless `server.allow_remote_shutdown` is true.
- `obsctl scene <alias|shortcut|obs-name>`: sends scene-change request to server.
- `obsctl mute <audio-target>`: sends mute request to server.
- `obsctl unmute <audio-target>`: sends unmute request to server.
- `obsctl toggle-mute <audio-target>`: sends toggle mute request to server.
- `obsctl vol <audio-target> <0-100>`: sends volume request to server.
- `obsctl dump-config`: sends dump-config request to server; server reads OBS state and writes config.
- `obsctl reload-config`: sends reload-config request to server.
- Scriptable commands accept `--json` for a single stdout JSON envelope with
  `ok`, `result`, `error`, and `exit_code`.

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

Public IPC error responses use the canonical codes `CONFIG_INVALID`,
`SERVER_UNAVAILABLE`, `OBS_UNAVAILABLE`, `REQUEST_TIMEOUT`,
`OBS_REQUEST_FAILED`, `SCENE_NOT_FOUND`, `AUDIO_INPUT_NOT_FOUND`,
`ALIAS_AMBIGUOUS`, `COMMAND_PARSE_ERROR`, `IPC_PROTOCOL_ERROR`,
`SHUTDOWN_DISABLED`, and `SERVER_ERROR`. Legacy vague boundary codes are
canonicalized before reaching CLI/TUI clients, and public messages must remain
secret-free.

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

Top-level `reconnect` is now canonical. Legacy `connection.reconnect` remains accepted for compatibility and is rewritten as top-level `reconnect` on config writes.

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
  - `obsctl status` (combined daemon plus OBS)
  - `obsctl obs-status` (OBS-only)
  - `obsctl server-status` (daemon-only)
  - `obsctl reconnect`
  - `obsctl shutdown-server` (guarded by `server.allow_remote_shutdown`)
  - `--json` envelope output for scriptable commands
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
  - `/obs-status`
  - `/server-status`
  - `/validate-config`
  - `/reconnect`
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
  - invalid server socket/pid paths
  - invalid reconnect delay policy values
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
  - preserves top-level `server` and `reconnect` daemon settings
  - adds missing OBS scenes/audio inputs
  - marks removed OBS objects as `stale: true`
  - backs up existing config before writing
  - can bootstrap a missing config file before connecting
  - reports duplicate aliases/shortcuts and alias/shortcut collisions with discovered OBS names before writing
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
- OBS Identify in server mode sends an explicit event subscription mask for General, Scenes, and Inputs events.
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
  - canonical public IPC error-code taxonomy with safe messages
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
  - command executor for validate-config, OBS reconnect requests, and guarded shutdown
  - subscription acknowledgement with an initial state event
  - persistent client registry for subscribed IPC sessions
  - state snapshot broadcast fanout after server-side OBS state changes
  - IPC remains available when OBS is unavailable
  - configured `server.socket_path` is honored by server, CLI clients, and TUI clients
- CLI IPC proxying:
  - non-interactive `status`, `obs-status`, `server-status`, `reconnect`, `shutdown-server`, `scene`, `mute`, `unmute`, `toggle-mute`, `vol`/`volume`, `dump-config`, and `reload-config` commands send typed IPC requests
  - `status` returns a combined daemon-and-OBS payload, while `obs-status` is OBS-only and `server-status` is daemon-only
  - JSON envelope output for scriptable commands uses stable `ok`, `result`, `error`, and `exit_code` keys
  - JSON failures carry canonical IPC error objects and return the same exit code reported in the envelope
  - CLI no longer creates an OBS WebSocket client for normal scriptable OBS-control commands
  - missing local server prints startup/service instructions and exits `3`
- Minimal ANSI TUI scaffold:
  - dashboard render
  - scenes panel output
  - audio panel output
  - raw character input loop when attached to a TTY
  - palette commands routed through the same parser as CLI
  - command palette open/edit/backspace/submit/cancel handling
  - dashboard shortcuts for quit, reload-config, and dump-config
  - basic first-run config creation when interactive config is missing
  - normal TUI sessions subscribe to server state over local IPC
  - TUI scene/audio commands are sent to the server over IPC
  - TUI `/reload-config` and `/dump-config` are server-performed IPC commands
  - TUI `/validate-config` and `/reconnect` are server-performed IPC commands
  - snapshot refresh after scene/audio commands
  - timer-based event polling in the ANSI TUI loop
  - server-pushed state events update the displayed snapshot
  - widgetized ANSI panels for connection, scenes, grouped scene map, audio, recent logs, and command palette
  - viewport-bounded ANSI rendering using terminal `COLUMNS`/`LINES` when available
  - incremental ANSI row-diff rendering after the initial TUI paint
  - recent server log-topic messages are retained in the TUI model and displayed in the dashboard
  - direct OBS session adapter remains available for explicit embedded-style use/tests
  - reconnect attempts use the configured reconnect policy
- Systemd user service support:
  - `obsctl service install`
  - `obsctl service uninstall`
  - `obsctl service status`
  - `obsctl service start`
  - `obsctl service stop`
  - `obsctl service restart`
  - install writes `~/.config/systemd/user/obsctl.service`
  - service unit uses the current absolute executable path with `server --headless`
  - install/uninstall run `systemctl --user daemon-reload`
- Runtime scaffolding:
  - logger with secret redaction
  - typed `--log-level debug|info|warn|error` parsing and filtering for persisted server logs
  - reconnect policy
  - scheduler
  - event loop placeholder
- Public documentation comments:
  - IPC, server, runtime, and systemd service public boundary types
  - config, OBS, domain, and TUI public boundary types
- Documentation:
  - `README.md`
  - `docs/config.md`
  - `docs/protocol.md`
  - `docs/commands.md`
- Specs currently covering:
  - config load/write
  - config validation
  - top-level `server` and `reconnect` config parsing/writing
  - legacy `connection.reconnect` compatibility
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
  - OBS client pending request failure on WebSocket close
  - TUI session command refresh behavior
  - TUI event application behavior
  - TUI reconnect-on-poll behavior
  - TUI IPC subscription and command forwarding behavior
  - TUI IPC pushed OBS event topic parsing
  - TUI IPC pushed server log topic parsing
  - TUI command palette input handling and dashboard shortcuts
  - TUI renderer panel output
  - TUI renderer viewport bounds and line truncation
  - TUI/CLI command parser coverage for server maintenance commands
  - CLI scene/audio integration against fake OBS server
  - CLI scene/audio integration through the local server IPC path
  - CLI dump-config integration through the local server IPC path
  - CLI dump-config conflict failure through the local server IPC path
  - CLI missing-server exit path for thin client commands
  - CLI JSON envelopes for success, server unavailable, parse errors, OBS unavailable, and command failures
  - CLI-level systemd service smoke coverage with a fake command runner hook
  - IPC codec validation
  - canonical IPC error-code validation, legacy-code canonicalization, and non-canonical-code rejection
  - IPC socket path resolution
  - IPC Unix socket request/response round trip
  - stale IPC socket cleanup
  - server IPC startup while OBS is unavailable
  - server-owned OBS scene command through IPC
  - server state transition to disconnected after an established OBS WebSocket closes
  - server state broadcasts to subscribed IPC clients
  - server OBS event and log topic broadcasts to subscribed IPC clients
  - server-side validate-config and guarded shutdown behavior
  - systemd user service unit generation and installer command behavior
  - daemon-first architecture boundary scans for normal CLI/TUI paths and server command execution
  - golden CLI and IPC contract fixtures for frozen command payloads, human output, JSON envelopes, and error behavior

## Partial

- Server:
  - foreground/headless runtime exists
  - OBS supervisor owns the OBS WebSocket client
  - IPC command executor can control scene/audio and dump/reload config
  - IPC command executor returns distinct combined, OBS-only, and daemon-only status payloads
  - IPC command executor validates config, handles explicit OBS reconnect requests, and rejects shutdown unless `server.allow_remote_shutdown` is enabled
  - reconnect loop detects established OBS WebSocket disconnects, marks state disconnected, clears the stale client, and retries when reconnect is enabled
  - supervisor lifecycle state is explicit: `start` marks the supervisor alive
    synchronously, accidental double starts are ignored while it is alive, and
    `stop` marks it stopped
  - supervisor run loops are generation-scoped: each `start` creates a fresh
    lifecycle generation, stale stopped generations exit without reclaiming an
    OBS client, and stop followed by immediate start keeps OBS ownership with
    the newest generation
  - explicit reconnect requests are generation-scoped durable request epochs:
    a request accepted by a live supervisor is consumed at the next legitimate
    retry boundary even when it arrives after a failed attempt but before the
    retry-delay wait starts; active-client-close wakes remain transient and
    cannot leak into a later unrelated retry delay
  - reconnect retry-delay waiting is delegated to `Server::ReconnectSignal`,
    whose waiter registration is atomic with the request-epoch check so an
    explicit reconnect request cannot be lost between checking the epoch and
    sleeping
  - `Server::ReconnectSignal` documents that the test-only waiter-registration
    probe is invoked while its internal lock is held; probe callbacks must not
    block or send on an unbuffered channel
  - explicit reconnect acceptance is lifecycle-gated with an accept-then-emit
    boundary: generation/lifecycle re-checks, reconnect request registration,
    active-client detachment, and public reconnect state mutation are decided
    under `@lifecycle_lock`, while detached OBS clients are closed immediately
    after that lock is released and before subscriber fanout, socket writes, or
    log publication can block
  - detached reconnect client cleanup is protected with `ensure`, so an
    unexpected state or log publication exception cannot skip closing the old
    OBS WebSocket client
  - accepted explicit reconnect requests use best-effort state/log publication:
    once a live supervisor accepts the request and detached-client cleanup has
    happened, subscriber publication failures are logged as sanitized
    diagnostics and do not change the command result
  - reconnect publication diagnostics write sanitized messages to the runtime
    logger first when configured; log-topic diagnostic fanout is secondary,
    opportunistic, detached, bounded, and lossy so blocked diagnostic delivery
    cannot delay an accepted reconnect command or accumulate unbounded parked
    fibers
  - server-owned `BestEffortLogBroadcast` caps outstanding reconnect
    diagnostic log-topic deliveries and drops new secondary diagnostics when
    capacity is exhausted; runtime logging remains the durable primary sink
  - aggregate dropped secondary reconnect diagnostic log-topic deliveries are
    exposed as `dropped_reconnect_diagnostic_logs` in daemon status and the
    combined status server object without changing reconnect command liveness
  - reconnect diagnostic log-topic fanout bypasses `Server#broadcast_log`, so
    primary runtime-log diagnostics are not duplicated when secondary delivery
    succeeds, while ordinary server log events still use the normal logs-topic
    path for TUI subscribers
  - stopped reconnect attempts expose a test-only, lifecycle-lock-guarded bit so
    specs can prove the simple sequential post-stop path returns `false`
    without publishing public reconnect state
  - `last_disconnected_at` is updated only after an established OBS session
    disconnects; `last_connection_failed_at` records the most recent failed OBS
    connection attempt and is not cleared by later successful connections
  - explicit `obsctl reconnect` keeps public `last_error` as
    `OBS reconnect requested` until the next connection success or failure
    outcome only when the running supervisor can perform a reconnect attempt;
    when the supervisor is sleeping in retry backoff or reaches the next retry
    boundary, explicit reconnect wakes or skips the backoff so the next OBS
    connection attempt runs promptly; if the supervisor has exited with
    reconnect disabled, the command returns `OBS_UNAVAILABLE` with the public message
    `OBS supervisor is not running; restart the server or enable reconnect.`
  - disconnect detection is event-driven through OBS client close/error
    notifications, with a defensive fallback timeout so cleanup and stop/cancel
    paths still make progress
  - protocol-error client closes are observed by the supervisor; stale OBS clients are dropped, OBS is marked disconnected, IPC stays available, and reconnect resumes when enabled
  - subscription handling maintains a client registry and broadcasts state, OBS event, and log topic updates
- CLI:
  - non-interactive OBS control commands are thin IPC clients
  - `status` is the combined daemon-and-OBS status command
  - `server-status` exists with PID, uptime, socket path, connected state, explicit reconnecting state, reconnect timestamps including `last_connection_failed_at`, last error, and subscribed client count
  - `status` and `server-status` human and JSON output include
    `dropped_reconnect_diagnostic_logs` as aggregate lossy secondary diagnostic
    fanout telemetry
  - `obs-status`, `reconnect`, and guarded `shutdown-server` are thin IPC client commands
- TUI:
  - currently a simple ANSI dashboard with raw key input and a command palette state machine
  - normal mode subscribes to the local server over IPC instead of creating an OBS WebSocket connection
  - not yet a full termisu dashboard
  - `termisu` is available as a Crystal shard, but its upstream README marks it as pre-1.0 and not battle-tested
  - not yet btop/btm-style keyboard-first layout
  - refreshes on a timer and uses row-level ANSI diff rendering after the first paint
  - compact recent-log panel displays server log-topic messages
- OBS client:
  - has a single WebSocket reader channel
  - has a pending request map for request/response coordination
  - fails in-flight pending requests promptly when the WebSocket closes or the reader fiber errors
  - explicitly closes the WebSocket and clears all pending requests after malformed OBS frames or response parser errors
  - pending-request specs cover late responses after timeout, concurrent requests, disconnects during in-flight requests, malformed frames, parser errors, and timeout cleanup
  - exposes connection state so the server supervisor can detect established WebSocket disconnects
  - exposes a bounded close/error notification primitive so the supervisor can
    wait for reader close, reader failure, malformed-frame close, or
    response-parser close without depending on fixed polling as the primary
    signal
  - event parsing exists and events are routed to a client channel
  - direct embedded-style TUI sessions can consume the event channel, and normal TUI mode consumes server-pushed IPC state, OBS event topics, and log topics
  - reconnect policy is still wired into the TUI session for server reconnects, but not into the low-level OBS client itself
- Config:
  - known fields round-trip
  - unknown top-level fields are explicitly rejected to avoid silent data loss
  - top-level `server` and `reconnect` sections are supported
  - legacy `connection.reconnect` is accepted and rewritten as top-level `reconnect`
  - dump-config preserves top-level `server` and `reconnect` settings and rejects alias/shortcut conflicts before writing
  - `validate-config` warns when plaintext `connection.password` is configured without printing the secret value
  - nested unknown fields are not preserved yet
- Logging:
  - logger exists with redaction and server-side log-level filtering
  - server lifecycle, supervisor, and command-failure log events are persisted when `obsctl server` is started through the CLI
  - non-server CLI/TUI paths do not yet consistently use it
- First run:
  - missing interactive config creates a safe default
  - no guided host/port/password prompt yet
  - no optional connect-and-dump flow yet
- Tests:
  - CLI scene/audio/dump-config fake-server specs exist
  - TUI session, IPC client, and command palette input specs exist
  - contract-freeze specs cover public IPC errors, JSON CLI envelopes, daemon-first boundaries, embedded TUI adapter require behavior, and golden CLI/IPC fixtures
  - optional `../obsctl-rs` compatibility checks skip cleanly in default mode when the sibling repository is absent or has no recognized fixture root
  - strict `obsctl-rs` compatibility mode fails clearly for missing sibling repositories, missing fixture roots, missing counterparts, and content differences
  - fake OBS server support exposes deterministic probes for Identify frames,
    OBS request types, close events, no-attempt windows, and
    connection-specific accepted/closed WebSocket ids
  - server reconnect specs cover initial OBS unavailable startup, reconnect-disabled supervisor exit, established-session disconnects, protocol-error disconnects, explicit reconnect requests, wakeable retry backoff, durable pre-delay reconnect requests, generation-safe stop/start ownership, stale reconnect wake invalidation, transient active-client-close wake behavior, and successful reconnects
  - server IPC/reconnect specs use `SpecSupport::TcpGate` instead of
    unavailable-then-bind `unused_tcp_port` windows, so default single-repo
    reconnect tests keep deterministic port ownership until fake OBS opens
  - server reconnect specs deterministically prove sequential reconnect-after-stop
    rejection without publishing stale public state such as
    `OBS reconnect requested`
  - server reconnect specs also prove the exact concurrent interleaving where
    reconnect observes a live generation, pauses before public publication,
    `stop` completes, reconnect resumes, and stale reconnect state remains
    unobservable
  - blocked reconnect-publication specs prove detached OBS client closure before
    or independently of releasing blocked state fanout, blocked log fanout, and
    unexpected state/log publication exceptions
  - reconnect diagnostic liveness specs prove accepted reconnects still
    complete after detached-client cleanup while diagnostic log-topic fanout is
    blocked; bounded-fanout coverage proves repeated blocked diagnostics reach
    the configured helper bound and drop excess work while later accepted
    reconnect commands still complete
  - command-level and server-level reconnect diagnostic specs prove sanitized
    diagnostics reach the runtime logger exactly once when secondary log-topic
    delivery succeeds, raises, or blocks
  - focused `BestEffortLogBroadcast` unit specs cover capacity validation,
    outstanding-count accounting, exception containment, drop accounting while
    full, and acceptance recovery after blocked workers are released
  - command executor, CLI, server, and golden contract specs cover
    `dropped_reconnect_diagnostic_logs` in daemon status and combined status
  - command-level reconnect specs prove raising state/log publication callbacks
    do not turn an accepted `reconnect_obs` command into `SERVER_ERROR`, while
    detached-client cleanup still happens and diagnostics remain sanitized
  - signal-level reconnect specs cover explicit request-before-wait,
    request-during-wait, handled-request stale wake behavior, transient internal
    wakes, cancel wakes, and repeated durable request epochs without needing a
    fake OBS server

## Not Yet Implemented

- Full termisu integration.
- Replace ANSI redraw backend with termisu after dependency integration is accepted.
- Low-level client reconnect loop independent of TUI session.
- Studio mode support.
- Stream/record controls and status.
- Scene item visibility controls.
- Volume meter events.
- `ameba` lint execution in this environment.
- Release packaging beyond `make release`.
- Unknown config field preservation.

## Milestone Tracking

### Milestone 1: CLI Skeleton

Done:

- shard project
- OptionParser
- config path resolution
- top-level server/reconnect config schema compatibility
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
- explicit event subscription options during Identify
- pending requests fail promptly on WebSocket close or reader failure
- pending requests are cleared on timeout, late response, concurrent request,
  disconnect, malformed frame, and response parser-error paths
- malformed OBS frames and response parser errors explicitly close the WebSocket
- established WebSocket disconnects are detected and surfaced by the server supervisor loop

Remaining:

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
- `obsctl status` returns combined daemon and OBS status
- `obsctl obs-status` returns OBS-only status
- `obsctl reconnect`
- guarded `obsctl shutdown-server`
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
- integration test against fake OBS server through the local server IPC path
- conflict reporting for duplicate aliases/shortcuts discovered during dump
- preservation of top-level `server` and `reconnect` settings during dump writes

Remaining:

- none currently

### Milestone 6: TUI MVP

Partial:

- minimal dashboard
- command loop
- scene/audio display
- widgetized ANSI connection/scenes/scene-map/audio/log/command panels
- palette command parser reuse
- session-owned client adapter
- snapshot refresh after successful scene/audio commands
- `/reload-config`
- `/dump-config` with model refresh
- server state subscription over local IPC in normal mode
- scene/audio/dump/reload commands forwarded to the server in normal mode
- raw-mode key input in terminal sessions
- command palette state for open/edit/backspace/submit/cancel
- keyboard shortcuts for quit, reload-config, and dump-config
- input controller specs
- recent server log display
- viewport-bounded rendering with line truncation
- incremental/diff rendering after the initial ANSI paint

Remaining:

- termisu app
- btop/btm-style layout polish beyond the current bounded ANSI panels

### Milestone 7: Realtime Events

Partial:

- scene changed events
- input mute changed events
- input volume changed events
- OBS event topic fanout from the server to IPC subscribers
- reconnect handling wired into runtime
- explicit OBS reconnect request command through IPC
- explicit reconnect requests are generation-scoped durable epochs that wake
  retry backoff or survive until the next retry boundary while the supervisor
  is alive
- reconnect retry-delay waiting uses an atomic `Server::ReconnectSignal`
  primitive, so request epochs cannot be lost between the pre-wait check and
  waiter registration
- supervisor stop/start ownership and reconnect request/wake state are
  generation-scoped
- reconnect publication uses an accept-then-emit boundary: reconnect acceptance
  and public state mutation remain generation-safe under the supervisor
  lifecycle lock, while detached OBS clients are closed immediately after the
  lock is released and before subscriber/log fanout can block
- reconnect detached-client cleanup is `ensure`-protected if state or log
  publication raises unexpectedly
- accepted reconnect publication is best-effort after lifecycle acceptance and
  detached-client cleanup; sanitized diagnostics are logged for subscriber
  delivery failures through the runtime logger first, secondary log-topic
  diagnostic fanout is opportunistic, non-blocking, bounded, and lossy, and
  public `reconnect_obs` responses remain successful
- the sequential post-stop reconnect rejection path is proven with a
  lifecycle-lock-guarded test hook plus state immutability assertions
- the concurrent reconnect-vs-stop interleaving is also proven: reconnect
  observes a live generation, pauses before publication, `stop` completes,
  reconnect resumes, and stale public reconnect state remains unobservable
- reconnect liveness specs cover blocked state fanout, blocked log fanout, and
  unexpected state/log publication exceptions while asserting the detached OBS
  client is still closed
- reconnect diagnostic liveness specs cover blocked diagnostic log-topic fanout
  for state and log publication failures, bounded outstanding diagnostic work
  with excess drops, and logger-fallback coverage proving sanitized diagnostics
  are persisted exactly once when diagnostic log-topic delivery succeeds,
  raises, or blocks
- focused `BestEffortLogBroadcast` unit specs cover constructor capacity
  validation, accepted-worker outstanding accounting, exception cleanup,
  drop-count increments while full, and acceptance after blocked workers drain
- aggregate dropped secondary reconnect diagnostic log-topic deliveries are
  observable through `dropped_reconnect_diagnostic_logs` in `server-status` and
  the combined `status` server object, with docs and golden fixtures updated
- command-level reconnect coverage proves raising state/log publication
  callbacks stay diagnostic-only after acceptance and never surface as
  `SERVER_ERROR`
- supervisor reconnect proof after protocol-error client closes while IPC remains available

### Milestone 8: Polish

Partial:

- README
- config docs
- protocol docs
- command docs
- frozen JSON CLI envelope docs
- canonical public IPC error-code docs
- daemon-first boundary docs
- stdout-only JSON envelope policy with secret-free stderr warnings
- public error-code-to-exit-code mapping docs
- plaintext password warning on `validate-config`
- viewport-bounded ANSI TUI rendering
- incremental ANSI TUI renderer backend
- public documentation comments for IPC, server, runtime, and systemd service public boundary types
- public documentation comments for config, OBS, domain, and TUI public boundary types
- test-only waiter-registration probe lock contract documented on
  `Server::ReconnectSignal`
- Makefile

Remaining:

- termisu renderer backend
- theme file
- packaging
- demo config
- ameba lint wiring after dependency install

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
- full `server-status` payload and CLI formatting for PID, uptime, socket path, subscribed client count, OBS connection state, explicit reconnecting state, reconnect timestamps including `last_connection_failed_at`, and last error
- persistent client registry and state broadcast fanout for subscriptions
- TUI IPC session client with subscription acknowledgement, initial state handling, command forwarding, and server-pushed state updates
- event/log topic broadcast fanout for server-side OBS events and command failures
- TUI IPC session client parsing of pushed OBS event topics
- TUI IPC request correlation for overlapping long-lived client commands, including out-of-order responses
- configured `server.socket_path` is honored by thin CLI/TUI clients
- IPC command executor supports `validate_config`, `reconnect_obs`, and guarded `shutdown_server`
- canonical public IPC error-code taxonomy and boundary canonicalization
- golden CLI/IPC contract fixtures for proxy command output, JSON envelopes,
  error envelopes, and IPC command payloads
- optional `../obsctl-rs` compatibility checks that skip by default when absent
  or when no recognized sibling fixture root exists
- strict `obsctl-rs` compatibility checks through `make contract-rs-compat`
  and `OBSCTL_STRICT_OBSCTL_RS_COMPAT=1`
- strict `obsctl-rs` GitHub Actions compatibility runs only by manual dispatch
  or scheduled cadence until the Rust-side fixture root exists, with repository
  owner/name/ref configurable by inputs or repository variables

Remaining:

- none currently

### Milestone 10: Systemd User Service

Done:

- `obsctl service install`
- `obsctl service uninstall`
- `obsctl service status`
- `obsctl service start`
- `obsctl service stop`
- `obsctl service restart`
- service unit generation with absolute `obsctl server --headless` ExecStart
- `systemctl --user daemon-reload` after install/uninstall
- service generation and installer specs
- CLI-level smoke coverage with a fake command runner hook

Remaining:

- none currently

## Planned Next

With reconnect lifecycle publication decoupled, detached-client cleanup ordered
before blockable fanout, publication-failure diagnostics now runtime-logger
primary with bounded, lossy, non-blocking secondary log-topic fanout, and the
reconnect flake cleanup slice removing port-window races plus polling-primary
disconnect detection, focused `BestEffortLogBroadcast` unit coverage and
aggregate reconnect diagnostic drop observability are now in place. The next
highest-value work moves back to contract ownership and contract-adjacent
polish.

1. Add or coordinate the Rust-side shared contract fixture root so the manual
   or scheduled strict compatibility workflow can become a required signal.
2. Run `make contract-rs-compat` separately in a prepared dual-repo workspace
   when `../obsctl-rs` is available with compatible contract fixtures.
3. Keep contract-adjacent polish next: review fixture wording and status
   examples for the new reconnect diagnostic drop field, then return to demo
   config, packaging polish, and optional `termisu` backend evaluation once the
   stabilized contract gates stay green.
