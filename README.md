# obsctl-cr

`obsctl-cr` is a Crystal 1.20 CLI/TUI for controlling OBS Studio through obs-websocket 5.x.

## Build

```sh
make build
```

The release binary target is `bin/obsctl`.

## Quick Start

```sh
bin/obsctl init
export OBS_WEBSOCKET_PASSWORD='your password'
bin/obsctl validate-config
bin/obsctl server --headless
bin/obsctl dump-config
bin/obsctl scene 1
bin/obsctl
```

Default config path on Linux is `~/.config/obsctl/config.yml`. Override with `--config` or `OBSCTL_CONFIG`.

Use `connection.password_env` for OBS WebSocket passwords. Plaintext `connection.password` is supported only when `password_env: ""` is configured; `validate-config` warns about plaintext passwords without printing the secret value.

Use `--log-level debug|info|warn|error` with `obsctl server` to control persisted server log verbosity. Logs are written to `~/.local/state/obsctl/obsctl.log` with password/authentication fields redacted.

## Commands

Scriptable commands:

```sh
obsctl server
obsctl server --headless
obsctl status
obsctl obs-status
obsctl server-status
obsctl reconnect
obsctl shutdown-server
obsctl scene <alias-or-name>
obsctl mute <alias-or-name>
obsctl unmute <alias-or-name>
obsctl toggle-mute <alias-or-name>
obsctl vol|volume <alias-or-name> <0-100>
obsctl dump-config
obsctl reload-config
obsctl validate-config
obsctl service install
obsctl service start|stop|restart|status|uninstall
```

Except for `init`, `validate-config`, `server`, and `service`, scriptable OBS-control commands are thin IPC clients. Start `obsctl server --headless` first; if the server is missing, commands print startup/service instructions and exit `3`. `shutdown-server` is disabled unless `server.allow_remote_shutdown: true` is set.

`obsctl status` reports combined local daemon and OBS status. Its JSON result
has a `server` object with daemon fields and an `obs` object with the OBS
snapshot.

`obsctl obs-status` reports only the OBS snapshot: connection state, current
scene, scenes, and audio inputs.

`obsctl server-status` reports only the local daemon status: PID, uptime,
socket path, subscribed client count, OBS connection state, explicit
reconnecting state, reconnect timestamps, and last error. `last_disconnected_at`
is set only after an established OBS session disconnects;
`last_connection_failed_at` records failed connection attempts before a session
is established. After `obsctl reconnect`, `last_error` remains
`OBS reconnect requested` until the next connection succeeds or fails.

`obsctl service install` writes `~/.config/systemd/user/obsctl.service` using the current executable path and runs `systemctl --user daemon-reload`. Service start/stop/restart/status/uninstall commands wrap `systemctl --user` and do not require `sudo`.

The TUI is also a local IPC client in normal mode. It subscribes to server state, OBS event, and log updates, and sends palette commands through the server using the same grammar with a leading slash, for example `/scene main`, `/mute mic`, `/vol mic 70`, `/validate-config`, and `/reconnect`. The current ANSI dashboard is split into connection, scenes, scene map, audio, recent logs, and command palette panels, with output bounded to the current `COLUMNS`/`LINES` terminal size when those environment values are available. After the first paint, the renderer updates only changed terminal rows. In a terminal, `/` or `:` opens the command palette, `Esc` cancels editing, `Enter` submits, `q` quits from the dashboard, `r` reloads config, and `D` dumps config through the server.

`dump-config` is performed by the local server, which owns the OBS connection, reads scenes and audio inputs, and writes a generated config. Existing config files are backed up before dump writes. The dump keeps top-level daemon settings such as `server` and `reconnect`, and it refuses to write if aliases or shortcuts would become ambiguous with discovered OBS names.

Config files reject unknown top-level fields so future settings are not silently lost during rewrites.

## Validation

Default Crystal validation runs the local contract suite without requiring a
sibling Rust checkout:

```sh
make test
crystal spec
```

Optional `obsctl-rs` golden-fixture compatibility is skipped by default when
`../obsctl-rs` is absent or when that sibling does not contain a recognized
contract fixture root. Run the strict dual-repo check explicitly with:

```sh
make contract-rs-compat
```

Strict mode sets `OBSCTL_STRICT_OBSCTL_RS_COMPAT=1` and fails on a missing
sibling repository, missing fixture root, missing counterpart files in either
repository, or content differences. `OBSCTL_SKIP_OBSCTL_RS_COMPAT=1` remains an
explicit override for skipping the optional compatibility check.
