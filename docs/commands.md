# Command Grammar

Palette commands start with `/`. Non-interactive CLI commands map to the same typed command parser.

Global options:

- `--config PATH`
- `--log-level debug|info|warn|error`
- `--force`
- `--json`

Required commands:

- `obsctl server`
- `obsctl server --headless`
- `obsctl status`
- `obsctl obs-status`
- `obsctl server-status`
- `obsctl reconnect`
- `obsctl shutdown-server`
- `obsctl scene <alias|shortcut|obs-name>`
- `obsctl mute <audio-alias|shortcut|obs-name>`
- `obsctl unmute <audio-alias|shortcut|obs-name>`
- `obsctl toggle-mute <audio-alias|shortcut|obs-name>`
- `obsctl vol|volume <audio-alias|shortcut|obs-name> <0-100>`
- `obsctl dump-config`
- `obsctl reload-config`
- `obsctl validate-config`
- `obsctl service install`
- `obsctl service uninstall`
- `obsctl service status`
- `obsctl service start`
- `obsctl service stop`
- `obsctl service restart`
- `/help`
- `/set-scene <alias|shortcut|obs-name>`
- `/scene <alias|shortcut|obs-name>`
- `/mute <audio-alias|shortcut|obs-name>`
- `/unmute <audio-alias|shortcut|obs-name>`
- `/toggle-mute <audio-alias|shortcut|obs-name>`
- `/vol <audio-alias|shortcut|obs-name> <0-100>`
- `/dump-config`
- `/reload-config`
- `/status`
- `/server-status`
- `/obs-status`
- `/validate-config`
- `/reconnect`
- `/connect`
- `/disconnect`
- `/quit`

Quoted names are preserved: `/scene "Main Camera"`.

`obsctl server` starts the foreground local server and owns the OBS WebSocket connection. `obsctl server --headless` runs the same server without interactive UI and is intended for a `systemd --user` service.

`--log-level` controls persisted server log verbosity when running `obsctl server`. Server logs are written to `~/.local/state/obsctl/obsctl.log`, and password/authentication fields are redacted before writing.

`obsctl service install` writes `~/.config/systemd/user/obsctl.service` with an absolute `ExecStart=<obsctl> server --headless`, then runs `systemctl --user daemon-reload`. The other service subcommands wrap `systemctl --user start|stop|restart|status obsctl.service`; uninstall removes the unit file and reloads systemd.

Non-interactive OBS control commands are IPC clients. They connect to the local Unix socket, send a typed command to the server, print the response, and exit. If the server is unavailable, they print startup/service instructions and exit `3`. `obsctl shutdown-server` is rejected unless `server.allow_remote_shutdown: true` is configured.

`--json` is available for scriptable commands: `status`, `obs-status`,
`server-status`, `reconnect`, `shutdown-server`, `scene`, `mute`, `unmute`,
`toggle-mute`, `vol`/`volume`, `dump-config`, `reload-config`, and
`validate-config`. The flag can be placed before the command or after the
command arguments:

```sh
obsctl --json status
obsctl scene main --json
```

JSON mode writes exactly one object to stdout:

```json
{"ok":true,"result":{"message":"Scene changed to Main Camera"},"error":null,"exit_code":0}
```

On failure, `ok` is `false`, `result` is `null`, `error` is a safe canonical
IPC error object, and `exit_code` matches the process exit code:

```json
{"ok":false,"result":null,"error":{"code":"SCENE_NOT_FOUND","message":"scene not found: missing"},"exit_code":4}
```

Human startup hints and other prose are not printed to stdout in JSON mode.
Secret-free human warnings may still be written to stderr in JSON mode. Human
diagnostics for non-JSON mode remain on stderr. If `--json` is used with a
command that does not support JSON output, such as `init` or `service`, obsctl
returns a JSON `COMMAND_PARSE_ERROR` envelope and exits `5` before performing
the command.

Canonical JSON/IPC error codes map to CLI exit codes as follows:

| Error code | Exit code |
| --- | ---: |
| `CONFIG_INVALID` | 2 |
| `SERVER_UNAVAILABLE` | 3 |
| `OBS_UNAVAILABLE` | 3 |
| `REQUEST_TIMEOUT` | 3 |
| `OBS_REQUEST_FAILED` | 4 |
| `SCENE_NOT_FOUND` | 4 |
| `AUDIO_INPUT_NOT_FOUND` | 4 |
| `ALIAS_AMBIGUOUS` | 5 |
| `COMMAND_PARSE_ERROR` | 5 |
| `IPC_PROTOCOL_ERROR` | 6 |
| `SHUTDOWN_DISABLED` | 5 |
| `SERVER_ERROR` | 1 |

`ALIAS_AMBIGUOUS` exits as command parse error code `5` because the user's
target is ambiguous before any OBS request is made.

`obsctl status` asks the local daemon for a combined status response. Human
output has separate `server:` and `obs:` sections. JSON output keeps the normal
single envelope and places the combined payload under `result.server` and
`result.obs`.

`obsctl obs-status` asks the local daemon for only the OBS snapshot. It is the
OBS-only command and is not an alias for the combined `status` command.

`obsctl server-status` checks only the local daemon. Its output includes `pid`,
`uptime_seconds`, `socket_path`, `client_count`, `obs_connected`,
`reconnecting`, `last_connected_at`, `last_disconnected_at`,
`last_reconnect_attempt_at`, `last_connection_failed_at`, `last_error`, and
`dropped_reconnect_diagnostic_logs`.
Timestamp fields are RFC3339 strings when known and `null` in JSON when absent.
`last_disconnected_at` is updated only when an established OBS session
transitions to disconnected. `last_connection_failed_at` is the timestamp of the
most recent failed OBS connection attempt. It can describe a previous failure
even while OBS is currently connected, and successful connections do not clear
it; only a newer failed attempt replaces it. `last_reconnect_attempt_at` records
when the supervisor last started an OBS connection attempt.
`dropped_reconnect_diagnostic_logs` is an aggregate counter for secondary
reconnect diagnostic `logs` topic messages that were dropped because bounded
best-effort fanout was full. Runtime logging is still the durable primary
diagnostic sink; the counter gives operators visibility into lossy subscriber
delivery without emitting one log entry per drop.

`obsctl reconnect` asks the running server supervisor to reconnect OBS. Success
means the running supervisor accepted a generation-scoped reconnect request, or
already has a prompt OBS connection attempt in progress; it does not mean OBS is
already connected. Accepted explicit requests are durable across the next retry
boundary, so a request made after a failed connection attempt but before retry
sleep starts is still acted on promptly. The public `last_error` stays
`OBS reconnect requested` until the next OBS connection success or failure
outcome. After the supervisor accepts the request and any detached OBS client is
closed, subscriber state/log delivery is best-effort. Publication failures are
logged as sanitized diagnostics and do not change the command result to
`SERVER_ERROR`:

```json
{"ok":true,"result":{"message":"OBS reconnect requested"},"error":null,"exit_code":0}
```

If the supervisor has already exited, such as after OBS was unavailable at
startup with `reconnect.enabled: false`, `obsctl reconnect` does not report a
requested reconnect. It fails with `OBS_UNAVAILABLE`, and server state continues
to report the real last connection failure instead of `OBS reconnect requested`:

```json
{"ok":false,"result":null,"error":{"code":"OBS_UNAVAILABLE","message":"OBS supervisor is not running; restart the server or enable reconnect."},"exit_code":3}
```

`obsctl validate-config` validates the local config file directly and does not require a running server. It prints a safe warning to stderr if plaintext `connection.password` is configured, including in JSON mode, and never echoes the password value. The TUI palette command `/validate-config` asks the running server to validate its configured file.

`obsctl dump-config` and `/dump-config` ask the server to fetch OBS scenes/audio inputs and rewrite the config with a backup. Dump writes preserve `server` and `reconnect` settings and fail with a config error if existing aliases or shortcuts would conflict with discovered OBS names.

`obsctl` and `obsctl tui` run the ANSI TUI as an IPC client in normal mode. The TUI subscribes to server state snapshots, OBS events, and server log topics, then forwards palette commands to the same server-owned command executor used by scriptable CLI commands. The dashboard renders connection, scenes, grouped scene map, audio, recent logs, and command palette panels. Rendering is bounded to the current `COLUMNS`/`LINES` terminal size when those environment values are available, so long scene/audio names and large collections do not overflow the viewport. After the initial full paint, the ANSI backend emits row-level diffs for changed content instead of clearing the whole screen every refresh.

The daemon-first boundary is enforced as a project contract: normal CLI source
and the normal TUI client path must not require or instantiate the OBS
WebSocket client implementation. Server-side `command_executor` is the
IPC-command-to-OBS-action boundary, and OBS WebSocket client construction stays
inside the server supervisor.

TUI keyboard input:

- `/` or `:` opens the command palette with the configured command prefix.
- `Backspace` edits the current palette line.
- `Enter` submits the current palette command.
- `Esc` or `Ctrl-C` cancels palette editing.
- `q` exits from the dashboard.
- `r` sends `/reload-config` from the dashboard.
- `D` sends `/dump-config` from the dashboard.
