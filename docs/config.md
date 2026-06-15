# Config Schema

The default path is `~/.config/obsctl/config.yml`. `OBSCTL_CONFIG` overrides it.

Top-level fields:

- `version`: currently `1`
- `server`: local daemon settings such as Unix socket path and remote shutdown policy
- `connection`: OBS WebSocket connection and timeout settings
- `reconnect`: daemon/TUI reconnect behavior
- `ui`: refresh interval, palette prefix, icon flag, theme name
- `scenes`: configured scene aliases, shortcuts, groups, and stale markers
- `audio.inputs`: configured audio aliases, shortcuts, kind, and stale markers
- `keymap`: keyboard bindings for the TUI

Minimal shape:

```yaml
version: 1
server:
  socket_path:
  pid_file:
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

Unknown top-level fields are rejected with a config error. This avoids silently dropping future fields when config files are rewritten. Nested unknown fields are currently ignored by the typed loader and are not preserved on write. Older configs with `connection.reconnect` are still accepted, but new writes use the top-level `reconnect` section.

Passwords should be provided through `connection.password_env`. By default this is `OBS_WEBSOCKET_PASSWORD`, and `validate-config` fails if a configured non-empty env var is missing. Plaintext `connection.password` is supported for compatibility, but to use it intentionally you must set `password_env: ""`. `validate-config` prints a warning when plaintext `connection.password` is configured and does not echo the secret value.

Scene lookup priority is shortcut, alias, exact OBS name, case-insensitive alias, then case-insensitive OBS name. Ambiguous matches fail without executing an action.

`dump-config` preserves existing aliases, shortcuts, groups, stale markers, and top-level daemon settings such as `server` and `reconnect`. Before writing, it reports duplicate aliases/shortcuts and alias/shortcut collisions with discovered OBS scene or audio names so a dump cannot save a config that would make later command lookup ambiguous.
