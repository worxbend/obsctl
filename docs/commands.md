# Command Grammar

Palette commands start with `/`. Non-interactive CLI commands map to the same typed command parser.

Global options:

- `--config PATH`
- `--log-level debug|info|warn|error`
- `--color auto|always|never`
- `--timeout SECONDS`
- `--force`
- `--json`
- `-q`, `--quiet`
- `-V`, `--version`
- `-h`, `--help`

Global options must precede the command. Everything after the command name
belongs to that command, so a subcommand flag such as `--topics` or
`--headless` is never intercepted by the global parser. `--json` is the one
exception: it is also accepted after the command arguments.

`--color` defaults to `auto`, which emits ANSI decoration only when stdout is a
terminal. Redirected or piped output is plain, and `NO_COLOR` (any non-empty
value) or `TERM=dumb` also disables it. `--color=always` forces decoration for
a pager that understands it.

`--quiet` suppresses human-readable stdout and leaves the exit code as the only
signal. It does not suppress `--json` output, which is an explicit request for
output, and it does not suppress warnings on stderr.

`--timeout` bounds a single daemon round trip and reports `REQUEST_TIMEOUT`
(exit `3`) when it elapses. Without it a command waits as long as the daemon
takes.

Required commands:

- `obsctl version` (also `obsctl --version`; supports `--json`)
- `obsctl doctor` (supports `--json`)
- `obsctl config explain` (supports `--json`)
- `obsctl config diff` (supports `--json`)
- `obsctl config migrate [--dry-run]` (supports `--json`)
- `obsctl watch [--topics state,events,logs]`
- `obsctl completions bash|zsh|fish`
- `obsctl completions candidates scenes|profiles|collections|audio`
- `obsctl init [--force]`
- `obsctl server`
- `obsctl server --headless`
- `obsctl status`
- `obsctl obs-status`
- `obsctl server-status`
- `obsctl reconnect`
- `obsctl shutdown-server`
- `obsctl scene|set-scene <alias|shortcut|obs-name>`
- `obsctl profile|set-profile <profile-name>`
- `obsctl collection|set-collection|scene-collection <collection-name>`
- `obsctl mute <audio-alias|shortcut|obs-name>`
- `obsctl unmute <audio-alias|shortcut|obs-name>`
- `obsctl toggle-mute <audio-alias|shortcut|obs-name>`
- `obsctl vol|volume <audio-alias|shortcut|obs-name> <0-100>`
- `obsctl stream`
- `obsctl rec|record` (toggles, unchanged)
- `obsctl rec|record start`
- `obsctl rec|record stop`
- `obsctl rec|record toggle`
- `obsctl rec|record pause`
- `obsctl rec|record resume`
- `obsctl rec|record status`
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
- `/profile <profile-name>`
- `/collection <collection-name>`
- `/themes` (also `/theme`, `/settings`)
- `/mute <audio-alias|shortcut|obs-name>`
- `/unmute <audio-alias|shortcut|obs-name>`
- `/toggle-mute <audio-alias|shortcut|obs-name>`
- `/vol <audio-alias|shortcut|obs-name> <0-100>`
- `/stream`
- `/rec` or `/record` (optionally `start|stop|toggle|pause|resume|status`)
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

Every command above is declared once, in `Domain::CommandRegistry`. The parser,
the `--json` allowlist, palette completion, `--help`, and the generated shell
completions all read that declaration, so the surfaces cannot disagree about
which commands exist or what they accept.

Non-interactive commands receive their arguments from the shell and pass them
to the parser unchanged, so a scene or input name may contain quotes,
backslashes, or any other character the shell delivers:

```sh
obsctl scene 'Camera "A"'
obsctl mute 'Mic\Aux'
```

In the palette there is no shell to do the splitting, so the line is tokenized:
whitespace separates arguments, double quotes group them, and inside quotes a
backslash escapes the next character. Quoted names are preserved:
`/scene "Main Camera"`. A volume percentage must not be quoted.

Control characters are rejected in any argument, and an argument is limited to
256 characters.

`obsctl server` starts the foreground local server and owns the OBS WebSocket connection. `obsctl server --headless` runs the same server without interactive UI and is intended for a `systemd --user` service.

`--log-level` controls server log verbosity when running `obsctl server`.
Server logs are written to `~/.local/state/obsctl/obsctl.log` and mirrored to
stderr for the running process. Password and authentication fields are redacted
before either sink receives an entry.

`obsctl service install` writes `~/.config/systemd/user/obsctl.service` with an absolute `ExecStart=<obsctl> server --headless`, then runs `systemctl --user daemon-reload`. The other service subcommands wrap `systemctl --user start|stop|restart|status obsctl.service`; uninstall removes the unit file and reloads systemd.

Non-interactive OBS control commands are IPC clients. They connect to the local Unix socket, send a typed command to the server, print the response, and exit. If the server is unavailable, they print startup/service instructions and exit `3`. `obsctl shutdown-server` is rejected unless `server.allow_remote_shutdown: true` is configured.

`--json` is available for every daemon command — `status`, `obs-status`,
`server-status`, `reconnect`, `shutdown-server`, `scene`, `profile`,
`collection`, `mute`, `unmute`, `toggle-mute`, `vol`/`volume`, `stream`,
`rec`/`record`, `dump-config`, `reload-config`, `validate-config`, including
every alias of each — plus the locally served `doctor`, `config`, and `watch`.
The flag can be placed before the command or after the command arguments:

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
`dropped_reconnect_diagnostic_logs` is process-local runtime telemetry and
resets when the daemon process restarts. It counts only dropped secondary
reconnect diagnostic `logs` topic deliveries from the bounded best-effort
fanout. Primary runtime logging is still the durable diagnostic sink, and
ordinary state, event, and log subscriber drops are not counted by this field.
The public value is a JSON-safe non-negative integer; values above
`Int64::MAX` are saturated to `Int64::MAX`. Human output renders the integer
reported by the daemon, including `0`, and renders `-` when an older daemon
omits the field. JSON output preserves the daemon payload and does not
synthesize the missing field.

`obsctl completions <shell>` prints a completion script for `bash`, `zsh`, or
`fish`. The script is generated from the command registry, so it always matches
the binary that produced it.

```sh
obsctl completions bash > /etc/bash_completion.d/obsctl
obsctl completions zsh  > "${fpath[1]}/_obsctl"
obsctl completions fish > ~/.config/fish/completions/obsctl.fish
```

Scene, profile, collection, and audio-input names are completed from the
running daemon. The scripts do that by calling `obsctl completions candidates
<kind>`, which prints one name per line; obsctl parses its own JSON rather than
asking each shell dialect to, because names can contain spaces, quotes, and
commas. The helper is bounded by a short timeout and prints nothing when the
daemon is unreachable, so completion never blocks or errors in the middle of a
command line.

`obsctl watch` streams daemon events to stdout as newline-delimited JSON, one
self-describing object per line. It is the scripting counterpart to the TUI:
consumers read it line-by-line without any framing logic. Writing to a closed
reader — `obsctl watch | head -5` — ends the stream normally and exits `0`.

```sh
obsctl watch | jq -r 'select(.topic == "state") | .data.current_scene'
```

Each line has exactly two fields. `data` is `null` when an event carries no
payload; the key is always present rather than omitted, so consumers do not
have to distinguish absent from null:

```json
{"topic":"state","data":{"connected":true,"current_scene":"Main Camera"}}
{"topic":"logs","data":{"level":"info","message":"OBS connected"}}
{"topic":"events","data":null}
```

Topics are `state`, `events`, and `logs`; all three are streamed by default.
`--topics` takes a comma-separated subset and rejects an unknown name rather
than silently streaming nothing:

```sh
obsctl watch --topics state,logs
```

Every line is flushed as it is written, so the stream is usable for reacting to
events as they happen. The command runs until interrupted or until the daemon
closes the connection, then exits `0`. If the daemon is not running it exits
`3`, like every other client command. `watch` always writes JSON, so `--json`
is accepted for consistency but changes nothing.

`obsctl config explain` prints every effective setting with the source that
supplied it, so it is clear which values the file actually sets and which are
falling through to defaults:

```text
connection.host           127.0.0.1               (file)
connection.port           4455                    (file)
ui.theme                  nord                    (file)
ui.locale                 null                    (default)
```

`obsctl config diff` prints only the settings where the file departs from the
built-in defaults, as `key: default -> current`. A key present on only one side
renders the missing side as `-`:

```text
ui.theme: default -> nord
```

It prints `config matches defaults: <path>` when there is nothing to report.

`obsctl config migrate` rewrites the file in the current canonical schema. It
drops top-level sections the current schema does not recognize, which is how a
config written for an older obsctl stops carrying settings that no longer do
anything, and it fills in keys the schema has since added:

```text
drop: legacy_setting
migrated: /home/user/.config/obsctl/config.yml
backup: /home/user/.config/obsctl/config.yml.bak.20260724192117
```

The original is always backed up to `<path>.bak.<timestamp>` before the rewrite,
and the write is atomic. `--dry-run` reports the same `drop:` and `add:` lines
without touching the file. Migrate is deliberately more tolerant than
`validate-config`: it accepts unknown top-level keys, because removing them is
the job. It still refuses a config that is invalid for any other reason, such
as a port outside the valid range.

Key paths are dotted and flattened from the canonical YAML. Sequences render
inline as `[a, b]`, so reordering a list does not appear as a settings change.

`obsctl doctor` checks the local setup and prints one line per check. It runs
without a daemon, so it is the first thing to run when something is wrong.

```text
[ok  ] version        obsctl 0.3.0
[ok  ] config         loaded /home/user/.config/obsctl/config.yml
[warn] credentials    connection.password_env is OBS_WEBSOCKET_PASSWORD, but that variable is unset or empty
                      -> export OBS_WEBSOCKET_PASSWORD in the environment that runs the daemon
[fail] daemon         no obsctl daemon is responding at /run/user/1000/obsctl/obsctl.sock
                      -> run: obsctl server --headless (or: obsctl service install)
```

Checks are `version`, `config`, `config.schema`, `credentials`, `socket`,
`daemon`, `obs`, and `service`. Each reports `ok`, `warn`, or `fail`:

- `warn` describes a setup that works but is worth changing, such as a
  plaintext password or a daemon that is not installed as a user service.
- `fail` means obsctl cannot do what you are asking of it.

Doctor exits `0` when no check failed, and `1` when any check failed. Warnings
alone do not fail the command. A failing check carries a remedy line; doctor
never prints a problem without saying what to do about it.

`--json` returns the same report as structured data. `result.healthy` mirrors
the exit status, and every entry has `name`, `status`, `detail`, and `remedy`
(null when there is nothing to do):

```json
{"ok":false,"result":{"healthy":false,"checks":[{"name":"daemon","status":"fail","detail":"no obsctl daemon is responding at /run/user/1000/obsctl/obsctl.sock","remedy":"run: obsctl server --headless (or: obsctl service install)"}]},"error":null,"exit_code":1}
```

Doctor never prints a password. The `credentials` check reports only which
source is configured and whether it resolves.

`obsctl record <action>` drives the OBS recording output. Bare `obsctl rec` and
`obsctl record` keep their original toggle behavior; the explicit actions are
`start`, `stop`, `toggle`, `pause`, `resume`, and `status`. The action is
case-insensitive. An unrecognized action is a parse error, not a silent toggle:

```text
unknown record action: bogus; expected start, stop, toggle, pause, resume, or status
```

Starting while already recording, or stopping while already stopped, is a no-op
in OBS rather than an error. `stop` reports the written file when OBS returns
one:

```json
{"ok":true,"result":{"message":"recording stopped: /home/user/Videos/take.mkv"},"error":null,"exit_code":0}
```

`obsctl record status` returns structured fields alongside the message, so
scripts do not parse prose. Human output renders one `key: value` line per
field, with `-` for anything the daemon reports as null:

```text
recording: active
timecode: 00:00:03.000
duration_ms: 3000
bytes: 4096
```

```json
{"ok":true,"result":{"message":"recording active","active":true,"paused":false,"timecode":"00:00:03.000","duration_ms":3000,"bytes":4096},"error":null,"exit_code":0}
```

`recording:` renders `active`, `paused`, `stopped`, or `-` when the daemon
cannot determine the state. `duration_ms` and `bytes` are only populated while
recording is active.

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

Startup first shows the responsive animated identity screen for two seconds;
any key dismisses it. `Ctrl-T` or `F2` opens the appearance lab, arrow keys (or
`j`/`k`) preview themes, Enter applies and atomically persists the selection,
and Esc restores the theme that was active when the lab opened.

The daemon-first boundary is enforced as a project contract: normal CLI source
and the normal TUI client path must not require or instantiate the OBS
WebSocket client implementation. Server-side `command_executor` is the
IPC-command-to-OBS-action boundary, and OBS WebSocket client construction stays
inside the server supervisor.

Cross-implementation status fixtures for `obsctl-rs` should live under one
recognized root such as `spec/fixtures/contracts/`, `tests/fixtures/contracts/`,
or `fixtures/contracts/`, with matching `cli/human/`, `cli/json/`, and `ipc/`
subdirectories. Current daemon status fixtures should include
`dropped_reconnect_diagnostic_logs`.

TUI keyboard input:

- `:` or the configured command prefix opens the command line, which keeps the
  key that opened it as its leader. Both leaders parse to the same commands and
  complete against the same registry.
- `Backspace` edits the current line; `Ctrl-U` clears it back to its leader and
  `Ctrl-W` deletes the last word.
- `Enter` submits the current command.
- `Tab`/`Shift-Tab` or `Ctrl-N`/`Ctrl-P` cycle completions.
- `Esc` or `Ctrl-C` cancels command-line editing.
- `:q`, `:qa`, `:wq`, `:x`, `:quit`, and `:exit` exit; `:h` lists the commands.
- `j`/`k` and the arrows move within a panel, `gg`/`G` jump to its ends, and
  `Ctrl-D`/`Ctrl-U` move half a panel.
- `Ctrl-W` followed by `h`/`j`/`k`/`l`, or `Ctrl` with those keys or the
  arrows, moves between panels.
- `Space` is the leader: `<leader>f` finds panels (`s`/`a`/`p`/`c`),
  `<leader>u t` opens themes, `<leader>o` sends OBS commands (`r` reload,
  `d` dump, `c` reconnect), `<leader>m` toggles mute, and `<leader>q` exits.
  A which-key menu lists the continuations while a sequence is pending; `Esc`
  or an unbound key cancels it.
- `q` exits from the dashboard.
- `r` sends `/reload-config` from the dashboard.
- `D` sends `/dump-config` from the dashboard.
- `Ctrl-T` or `F2` opens theme settings; arrows or `j`/`k` preview, Enter
  persists, and Esc cancels the preview.

TUI mouse input:

- Clicking a dashboard row focuses and selects it; clicking the selected row
  activates it. Clicking an input's speaker glyph toggles its mute.
- The wheel is a gain control over the audio matrix and a cursor move over the
  other panels; `Shift` with the wheel moves through the audio list.
- Clicking a which-key entry runs its binding or opens its group; clicking
  elsewhere cancels the sequence.
- Clicking a completion chip puts it on the command line, the wheel cycles
  completions, and a click outside the panel closes the line.
- In theme settings a click previews the theme under the pointer, a second
  click on it persists the selection, and the wheel moves through the list.
