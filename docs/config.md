# Config Schema

The default path is `~/.config/obsctl/config.yml`. `OBSCTL_CONFIG` overrides it.

Top-level fields:

- `version`: currently `1`
- `server`: local daemon settings such as Unix socket path and remote shutdown policy
- `connection`: OBS WebSocket connection and timeout settings
- `reconnect`: daemon/TUI reconnect behavior
- `ui`: refresh interval, palette prefix, icon flag, theme name, locale
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
ui:
  refresh_interval_ms: 250
  command_palette_prefix: "/"
  advanced_ui: true
  show_icons: true
  theme: default
  locale: en
```

The TUI accepts 29 built-in themes matching the Rust reference. Set `theme:
custom` and add any subset of `custom_theme` colors (`bg`, `accent`,
`accent_alt`, `fg`, `muted`, `border`, `border_focus`, `success`, `warning`,
`danger`, `info`, `highlight_bg`, and `highlight_fg`) as six-digit RGB hex.
Missing or invalid custom values fall back to the default Claude palette.

The TUI supports `en` and `uk` for the localized header and connection
surface, matching the Rust reference. Set `ui.locale`, or override it for one
process with `OBSCTL_LOCALE`; the environment value takes precedence and
unsupported values fall back to English.

Unknown top-level fields are rejected with a config error. This avoids silently dropping future fields when config files are rewritten. Nested unknown fields are currently ignored by the typed loader and are not preserved on write. Older configs with `connection.reconnect` are still accepted, but new writes use the top-level `reconnect` section.

Passwords should be provided through `connection.password_env`. By default this
is `OBS_WEBSOCKET_PASSWORD`. When the variable is absent or empty, obsctl uses a
configured plaintext `connection.password` fallback, if any, and otherwise
uses an empty password. If OBS sends an authentication challenge, obsctl answers
that challenge using the empty password; otherwise it identifies without an
authentication field. `validate-config`
prints a warning when plaintext `connection.password` is configured and does
not echo the secret value.

Scene lookup priority is shortcut, alias, exact OBS name, case-insensitive alias, then case-insensitive OBS name. Ambiguous matches fail without executing an action.

`dump-config` preserves existing aliases, shortcuts, groups, stale markers, and top-level daemon and appearance settings such as `server`, `reconnect`, and `ui`. Before writing, it reports duplicate aliases/shortcuts and alias/shortcut collisions with discovered OBS scene or audio names so a dump cannot save a config that would make later command lookup ambiguous.
