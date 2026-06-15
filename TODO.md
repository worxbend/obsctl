# obsctl-cr Implementation Tracker

This tracker is grounded in the initial project brief. It records what is implemented, what is partial, what remains, and the next planned work.

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
  - `obsctl scene <target>`
  - `obsctl mute <target>`
  - `obsctl unmute <target>`
  - `obsctl toggle-mute <target>`
  - `obsctl volume <target> <0-100>`
  - `obsctl status`
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
- Minimal ANSI TUI scaffold:
  - dashboard render
  - scenes panel output
  - audio panel output
  - command loop
  - palette commands routed through the same parser as CLI
  - basic first-run config creation when interactive config is missing
  - session-owned OBS client adapter
  - snapshot refresh after scene/audio commands
  - `/reload-config` reloads config and reconnects
  - `/dump-config` writes merged config and refreshes the model
  - timer-based event polling in the ANSI TUI loop
  - scene/audio OBS events update the displayed snapshot
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
  - CLI scene/audio integration against fake OBS server

## Partial

- TUI:
  - currently a simple ANSI dashboard and line-based command loop
  - not yet a full termisu dashboard
  - not yet btop/btm-style keyboard-first layout
  - does not yet do raw-mode key handling
  - refreshes on a timer, but rendering is still full-screen ANSI redraw
- OBS client:
  - has a single WebSocket reader channel
  - has a pending request map for request/response coordination
  - event parsing exists and events are routed to a client channel
  - event channel is consumed by the TUI session
  - reconnect policy is wired into the TUI session, but not into the low-level client itself
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
  - TUI session specs exist, but no raw keyboard/input specs yet

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
- `obsctl status`

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

## Planned Next

1. Add explicit OBS event subscription options during Identify.
2. Add dump-config CLI integration coverage against the fake OBS server.
3. Improve close/error handling for pending requests and WebSocket shutdown.
4. Add raw-mode keyboard handling and a real command palette.
5. Evaluate/install `termisu` if available and replace ANSI rendering with proper widgets.
6. Add public documentation comments and run lint once dependencies are installed.
