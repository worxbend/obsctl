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
bin/obsctl dump-config
bin/obsctl scene 1
bin/obsctl
```

Default config path on Linux is `~/.config/obsctl/config.yml`. Override with `--config` or `OBSCTL_CONFIG`.

Use `connection.password_env` for OBS WebSocket passwords. Plaintext `connection.password` is supported only when `password_env: ""` is configured, and the CLI does not yet emit a separate plaintext-password warning.

## Commands

Scriptable commands:

```sh
obsctl status
obsctl scene <alias-or-name>
obsctl mute <alias-or-name>
obsctl unmute <alias-or-name>
obsctl toggle-mute <alias-or-name>
obsctl volume <alias-or-name> <0-100>
obsctl dump-config
obsctl validate-config
```

TUI palette commands use the same grammar with a leading slash, for example `/scene main`, `/mute mic`, and `/vol mic 70`.

`dump-config` can bootstrap a missing config file by connecting to OBS, reading scenes and audio inputs, and writing a generated config. Existing config files are backed up before dump writes.

Config files reject unknown top-level fields so future settings are not silently lost during rewrites.
