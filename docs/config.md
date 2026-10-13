# Config Schema

The default path is `~/.config/obsctl/config.yml`. `OBSCTL_CONFIG` overrides it.

Top-level fields:

- `version`: currently `1`
- `server`: local daemon settings such as Unix socket path and remote shutdown policy
- `connection`: OBS WebSocket connection and timeout settings
- `reconnect`: daemon/TUI reconnect behavior
- `ui`: refresh interval, palette prefix, mouse capture, icon flag, theme name, locale
- `scene_profiles` / `active_scene_profile`: named sets of scene-visibility choices
- `scenes`: configured scene aliases, shortcuts, groups, and stale markers
- `audio.inputs`: configured audio aliases, shortcuts, kind, and stale markers
- `keymap`: dashboard key bindings

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
  mouse: true
  advanced_ui: true
  show_icons: true
  theme: default
  locale: en
# Optional, and top-level rather than under `ui:` -- these describe the `scenes:`
# list above them. Left out entirely when no scene profile has been created.
scene_profiles:
  - name: streaming
    hidden:
      - Utility Cam
      - BRB Loop
  - name: editing
    hidden: []
active_scene_profile: streaming
keymap:
  quit: ["q", "ctrl+c"]
  command_palette: ["/", ":"]
  reload_config: ["r"]
  dump_config: ["D"]
```

`keymap` is part of the on-disk schema and round-trips through `config
migrate`, so a config written by the Rust reference loads unchanged. The
dashboard still resolves these four actions from its built-in bindings, which
are the defaults shown above, so overriding them does not change what the keys
do yet.

Configs can be shared with `obsctl-rs`. Both preserve server options, audio
`kind`, scene profiles, keymap overrides, and `ui.mouse` during rewrites.
`ui.mouse: false` disables terminal mouse capture so text selection works.
The Rust daemon preserves `server.pid_file` and `server.start_embedded_if_missing`
for compatibility but does not act on them. Theme IDs beyond the common palette
set and keymap overrides can behave differently between dashboards.
An omitted `version` defaults to `1`. An omitted `connection.password_env`
uses `OBS_WEBSOCKET_PASSWORD`; an explicit empty or null value disables that
environment lookup. Top-level `reconnect` takes precedence over legacy
`connection.reconnect`, including when the top-level section is empty.

The TUI accepts 41 built-in themes: the 29 matching the Rust reference, plus 12
`vivid` palettes — near-black grounds under a two-colour gradient that changes
hue rather than shade (`toxic-violet`, `ember-riot`, `acid-rain`,
`neon-crimson`, `plasma-drift`, `ultraviolet`, `radioactive`, `blood-orange`,
`hyperdrive`, `nightshade`, `magma-core`, `dusk-riot`). Set `theme:
custom` and add any subset of `custom_theme` colors (`bg`, `accent`,
`accent_alt`, `fg`, `muted`, `border`, `border_focus`, `success`, `warning`,
`danger`, `info`, `highlight_bg`, and `highlight_fg`) as six-digit RGB hex.
A missing or invalid value falls back to the default Ember palette, except for
`highlight_bg` and `highlight_fg`, which are derived from your own colors as
described below.

`highlight_bg` and `highlight_fg` are the selection bar — the block drawn
behind the row the cursor is on. Set either one and that color is used as
given. Leave them out and they are derived:

- `highlight_bg` is your `accent` mixed 28% into your `bg`, which is how a
  terminal with no alpha channel gets a see-through highlight.
- `highlight_fg` is whichever of your `fg` and your `bg` has more contrast
  against the resulting bar. Those two settings are halves of one decision, so
  setting a bright `highlight_bg` and leaving `highlight_fg` unset would
  otherwise put light text on a light bar.

A span whose own color cannot be read on the bar — a row index in `muted`, say
— is redrawn in `highlight_fg` for that row only, so the selected row stays
legible whatever the bar turns out to be.

The `mono` palette is the exception and keeps a solid reversed bar, because a
tint is not guaranteed to be visible on a 16-color terminal.

The TUI supports `en` and `uk` for the localized header and connection
surface, matching the Rust reference. Set `ui.locale`, or override it for one
process with `OBSCTL_LOCALE`; the environment value takes precedence and
unsupported values fall back to English.

A large OBS setup often contains scenes that exist only to be referenced by
other scenes — a lower-third, a background loop, a nested camera group. They are
real scenes, but you never switch to them, so they are noise in the dashboard's
scene list.

`scene_profiles` is how you get rid of that noise. A *scene profile* is a name
plus a list of scene names to leave out of the list: `streaming` in the example
above hides `Utility Cam` and `BRB Loop`, while `editing` hides nothing.
`active_scene_profile` names the profile in effect. Profiles are obsctl's own
filter over the scene list. They are not OBS profiles and not OBS scene
collections — those are OBS's own concepts, the dashboard shows them in their own
panels, and nothing here is ever sent to OBS.

Names are matched with surrounding whitespace trimmed and ASCII letters compared
case-insensitively, so `active_scene_profile: "  STREAMING  "` finds a profile
saved as `streaming`. The spelling stored under `name:` is the one obsctl reports
back and writes to the file; matching loosely never rewrites it.

Which scenes the dashboard draws is decided by one of two rules, never both:

- **A profile is active.** That profile is the complete answer: every scene except
  the ones it lists is shown, and the per-scene `hidden` flag under `scenes:` is
  not consulted. This is what lets a profile *reveal* a scene that `scenes:` marks
  hidden, and what makes "show every scene" expressible as a profile whose
  `hidden:` list is empty. Adding the two lists together could do neither.
- **Nothing is active** — the keys are absent, `active_scene_profile` is unset, or
  it names a profile that is not in `scene_profiles`. Then scenes marked
  `hidden: true` under `scenes:` are left out and everything else is shown.

The **daemon** resolves that rule, not the dashboard. It reports every scene it
knows about and marks each one hidden or not, so every client — a dashboard, a
second dashboard, the CLI — draws the same list, and a profile switched anywhere
takes effect everywhere without a reload. `obsctl status --json`, `obsctl
obs-status --json` and `obsctl completions candidates scenes` still list every
scene OBS has; the per-scene `hidden` flag is what changes.

Two profiles whose names differ only in case or padding, a profile with a blank
name, and a name carrying control characters or longer than 256 characters are
all rejected as config errors — `active_scene_profile` could not name one of a
colliding pair unambiguously. Two things are warnings rather than errors, because
either would otherwise empty a scene list over a typo:

- `active_scene_profile` naming a profile that is not defined.
- A profile hiding a scene that is not in the `scenes:` list. Skipped entirely
  when `scenes:` is empty, which is what a fresh `obsctl init` writes.

Profiles can be managed from the CLI with `obsctl scene-profile`, and from the
dashboard, where the two halves of the feature have a key each. `<leader>p` opens
the scene profile list: it names every saved profile plus a "Show every scene"
row, puts the one under the cursor into effect, and renames or deletes it.
`<leader>P` opens the scene profile editor, which lists every scene with the
hidden ones dimmed and toggles one with `t`, so it is where a profile's `hidden`
list is chosen. Both ask the daemon, which is what writes this file.

Saving a profile does not activate it — the editor lets you work on a profile you
are not currently using, and switching the scene list out from under you would be
a surprise. `<leader>p` is how a profile is put into effect.

Both keys are omitted when there is nothing in them, so a config file that has
never used the feature is rewritten unchanged by `config migrate` and
`dump-config`. (The Rust implementation writes `scene_profiles: []` and
`active_scene_profile: null` instead of leaving them out. Both sides default the
keys to empty when reading, so the two agree on meaning and differ only in
whether they spell the default out.)

`dump-config` carries profiles across untouched. It learns which scenes OBS has
now, but it never reconciles a profile's `hidden:` list against them: a profile
naming a scene that has gone is left alone and only draws the warning above.

Unknown top-level fields are rejected with a config error. This avoids silently dropping future fields when config files are rewritten. Nested unknown fields are currently ignored by the typed loader and are not preserved on write. Older configs with `connection.reconnect` are still accepted, but new writes use the top-level `reconnect` section.

Passwords should be provided through `connection.password_env`. By default this
is `OBS_WEBSOCKET_PASSWORD`. When the variable is absent or empty, obsctl uses a
configured plaintext `connection.password` fallback, if any, and otherwise
uses an empty password. If OBS sends an authentication challenge, obsctl answers
that challenge using the empty password; otherwise it identifies without an
authentication field. `validate-config`
prints a warning when plaintext `connection.password` is configured and does
not echo the secret value.

Set that variable in the environment of the process that runs the daemon, not in
a shell startup file: `~/.bashrc` and friends are usually world-readable, are
often committed to a public dotfiles repository, and export the value to every
process the shell starts. Read it from a password manager on the command that
launches the daemon, or from an `EnvironmentFile=` with mode `600` in a systemd
drop-in under `~/.config/systemd/user/obsctl.service.d/`.

Scene lookup priority is shortcut, alias, exact OBS name, case-insensitive alias, then case-insensitive OBS name. Ambiguous matches fail without executing an action.
Scene and audio names discovered in the current OBS snapshot remain selectable
even when they do not yet have entries in the config; configured aliases and
shortcuts keep their normal priority.

`dump-config` preserves existing aliases, shortcuts, groups, stale markers, and top-level daemon and appearance settings such as `server`, `reconnect`, and `ui`. Before writing, it reports duplicate aliases/shortcuts and alias/shortcut collisions with discovered OBS scene or audio names so a dump cannot save a config that would make later command lookup ambiguous.
