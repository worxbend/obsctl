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

Use `connection.password_env` for OBS WebSocket passwords. Plaintext `connection.password` is supported only when `password_env: ""` is configured, and the CLI does not yet emit a separate plaintext-password warning.

## Commands

Scriptable commands:

```sh
obsctl server
obsctl server --headless
obsctl status
obsctl server-status
obsctl scene <alias-or-name>
obsctl mute <alias-or-name>
obsctl unmute <alias-or-name>
obsctl toggle-mute <alias-or-name>
obsctl vol|volume <alias-or-name> <0-100>
obsctl dump-config
obsctl reload-config
obsctl validate-config
```

Except for `init`, `validate-config`, and `server`, scriptable commands are thin IPC clients. Start `obsctl server --headless` first; if the server is missing, commands print startup/service instructions and exit `3`.

The TUI is also a local IPC client in normal mode. It subscribes to server state updates and sends palette commands through the server, using the same grammar with a leading slash, for example `/scene main`, `/mute mic`, and `/vol mic 70`.

`dump-config` is performed by the local server, which owns the OBS connection, reads scenes and audio inputs, and writes a generated config. Existing config files are backed up before dump writes.

Config files reject unknown top-level fields so future settings are not silently lost during rewrites.
