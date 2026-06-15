# Config Schema

The default path is `~/.config/obsctl/config.yml`. `OBSCTL_CONFIG` overrides it.

Top-level fields:

- `version`: currently `1`
- `connection`: OBS WebSocket connection and timeout settings
- `ui`: refresh interval, palette prefix, icon flag, theme name
- `scenes`: configured scene aliases, shortcuts, groups, and stale markers
- `audio.inputs`: configured audio aliases, shortcuts, kind, and stale markers
- `keymap`: keyboard bindings for the TUI

Unknown top-level fields are rejected with a config error. This avoids silently dropping future fields when config files are rewritten. Nested unknown fields are currently ignored by the typed loader and are not preserved on write.

Passwords should be provided through `connection.password_env`. By default this is `OBS_WEBSOCKET_PASSWORD`, and `validate-config` fails if a configured non-empty env var is missing. Plaintext `connection.password` is supported for compatibility, but to use it intentionally you must set `password_env: ""`. The current CLI does not yet emit a separate warning for plaintext passwords, so avoid storing secrets in the config file.

Scene lookup priority is shortcut, alias, exact OBS name, case-insensitive alias, then case-insensitive OBS name. Ambiguous matches fail without executing an action.
