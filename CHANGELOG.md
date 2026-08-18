# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`shard.yml` and `src/obsctl/version.cr` carry the version currently in
development; the `Unreleased` section below becomes that version at tag time.

## [0.8.0] - 2026-08-18

### Added

- A scene picker on `<leader>s`, so switching scene costs two keystrokes
  instead of a cursor walk: the overlay lists every scene beside a single key
  that switches to it, labelled `1`-`9` and then `a`-`z`. A scene configured
  with a single-character `shortcut` claims that key ahead of the automatic
  sequence, because the scenes panel already advertises it as `[b]` and the two
  surfaces must not disagree about which key reaches a scene; multi-character
  shortcuts are left to the command line, which can accept them. The picker
  captures every key while open — `q` and `m` are scene labels in there, not
  quit and mute — and an unlabelled key is ignored rather than closing it, so a
  typo costs one keystroke. Arrows and `Enter` reach the scenes past the
  thirty-fifth label, clicking a row switches to it, and the picker refuses to
  open with no scenes rather than swallowing keys for an empty box.
- A status beacon in the top-right corner of the header. Each output state
  gets a motion of its own rather than only a colour, because the corner has
  to be readable out of the edge of an eye and on a terminal whose palette
  cannot be trusted: nothing moves while OBS is away, a lone arc drifts back
  and forth while idle, the bar breathes in place while recording, arcs run
  outwards from the centre while streaming, and they chase in one direction
  when both outputs are live. The badge beside it names the state and counts
  the elapsed time. The beacon is given a column of the header rather than
  drawn over it, and asks only for the width its own badge needs, so a long
  scene or profile name can never run underneath it; on a header too narrow to
  afford both, the beacon drops out and the status line keeps every column.
  Plain (`advanced_ui: false`) terminals keep every cadence in ASCII rather
  than losing the animation.
- Twelve `vivid` themes — `toxic-violet`, `ember-riot`, `acid-rain`,
  `neon-crimson`, `plasma-drift`, `ultraviolet`, `radioactive`,
  `blood-orange`, `hyperdrive`, `nightshade`, `magma-core` and `dusk-riot`.
  Near-black grounds under a two-colour gradient that changes hue rather than
  shade, since the header, panel titles and splash all blend `accent` into
  `accent_alt` and a pair that only differs in brightness renders as a flat
  title. The reference catalog still opens the theme picker in its own order
  and `mono` still closes it, so an existing `theme:` setting is unaffected.

### Changed

- The first-run guide no longer tells you to export `OBS_WEBSOCKET_PASSWORD`
  from `~/.bashrc` or `~/.zshrc`. Shell startup files are usually mode `644`,
  are routinely published in a dotfiles repository, and hand the variable to
  every process started from that shell rather than to the daemon alone. The
  README, the website, `docs/config.md` and `SECURITY.md` now show `read -rs`
  for the current shell, and — for a password that has to survive a reboot —
  reading it from a password manager on the launch command, or from a mode
  `600` `EnvironmentFile=` in a systemd drop-in under
  `~/.config/systemd/user/obsctl.service.d/`, which `obsctl service install`
  leaves alone when it rewrites the unit.
- The README and the website show a recording of a real session instead of
  rendered screenshots. `docs/demo/obsctl.cast` is an
  [asciinema](https://asciinema.org) cast — a terminal session stored as text
  rather than as pixels — of an unedited `obsctl tui` run, trimmed to the
  session itself. The website plays it with a vendored asciinema player, so it
  stays sharp at any size and can be paused, scrubbed and copied out of; the
  README embeds `docs/demo/obsctl.gif`, because GitHub cannot play a cast
  inline. A still frame goes stale the moment a panel is redrawn and nothing
  catches it, and half of what the dashboard is — spinners, meters, the
  gradient chrome, the beacon — cannot be shown in one. The recipe for
  re-recording and re-rendering both files is in `docs/demo/README.md`.
- The command line types a result out three times faster — nine graphemes per
  animation tick rather than three. The reveal is there to draw the eye to a
  new message, and at the old rate a long error string took long enough to
  finish that it read as something to wait through instead.
- `make site-frames` is now `make site-themes`, and it writes `site/themes.js`
  instead of `site/frames.js`. The website no longer renders dashboard frames
  of its own, so the generator only exports the theme palettes the page
  restyles itself from — 2 KB of colours rather than 312 KB of pre-rendered
  HTML. The Pages workflow still fails if the committed copy is stale.

- Internal restructuring, with no change to the command line, the dashboard,
  the IPC protocol or the config format. The obs-websocket connection (socket,
  handshake, frame routing, request correlation) is now `OBS::Transport`,
  separate from the `OBS::Client` façade of OBS operations that sits on it.
  OBS events are translated into typed values before the daemon's supervisor
  sees them, so the vendor's wire format stops leaking into supervision logic,
  and disconnect log codes are derived from the error's type rather than by
  matching regular expressions against its message — reword a diagnostic and
  the `code` operators alert on no longer changes underneath them. IPC command
  names, the local (non-daemon) command surface, and both halves of the `state`
  topic payload are each now declared in exactly one place instead of being
  repeated across four or five files that nothing kept in step; specs check
  each of those single sources against the code that consumes it, and a new
  spec pins the round trip from a daemon-side exception to the process exit
  code the shell sees.

### Fixed

- The daemon's Unix socket is owner-only from the moment it exists. It used to
  be created at whatever the process umask allowed — group- and world-readable
  on a typical desktop — and corrected to mode `600` immediately afterwards,
  which leaves a brief window at the wrong permissions. Nothing could reach
  through that window in practice, because the socket's parent directory is
  mode `700` and a socket cannot be opened through a directory you cannot
  enter, but that left one guarantee resting on a defence that was not about
  the socket itself. `bind` now narrows the umask around socket creation, and
  keeps the `chmod` as a fallback for any platform that ignores it.

### Removed

- The rendered screenshots and the code that produced them: `make
  readme-shots`, `scripts/render_readme_shots.cr`,
  `scripts/render_site_frames.cr`, `scripts/support/showcase.cr`, and the five
  SVGs under `docs/assets/`. The recording replaces all of them.

## [0.7.0] - 2026-08-07

### Fixed

- A config with a `keymap:` section loads instead of failing with
  `unsupported top-level config field: keymap`. The field has been documented
  as part of the schema all along and is written by the Rust reference, but the
  loader's allow-list never learned about it, so any config carrying one was
  rejected outright with exit code 2. It is now typed, defaulted, and written
  back out by `config migrate`, so a hand-written or Rust-written file
  round-trips without losing its bindings. The dashboard still resolves those
  four actions from its built-in bindings — which are the defaults — so
  overriding them does not change what the keys do yet.

### Changed

- The audio matrix is a mixing desk rather than a list. Each input is a
  vertical channel strip — name, meter, fader, dB and gain readouts, mute
  button — and the strips sit side by side, scrolling sideways to keep the
  selected channel on screen. The meter fills bottom-up in eighth-height
  blocks, so it resolves to eight times the rows the panel has, and colours
  each cell by the level that cell stands for: green to −20 dBFS, yellow to
  −9, red above it, the way OBS does. A peak marker jumps to the loudest
  reading and slides back down on the clock rather than with the signal, a
  clipping channel flashes its name, and a channel that has never reported a
  level shows a searching dot instead of an empty column, so "no signal" reads
  differently from "silent". Panels give up rows from the bottom as they
  shrink — dB readout first, then gain, then the mute button — and the meter is
  the last thing to go.

  The keys turned with the layout. On the audio matrix `←`/`→` and `h`/`l` now
  move between channels and `↑`/`↓` and `k`/`j` ride the gain of the selected
  one, which is the way the strips are actually arranged; every other panel is
  still keyed as a list. `Ctrl` with those keys still leaves the panel, and
  `gg`/`G`, `Home`/`End` and the half-panel keys still move between channels.
  The mouse follows the same layout: a channel is picked out by column, the
  wheel is a gain control over any part of a strip, and the mute button is the
  row at its foot.

- The README is written for someone who has never enabled obs-websocket
  before: a one-line install at the top, a five-step first run that says which
  OBS menu to open and what should happen after each step, cheat sheets instead
  of prose, and a symptom-to-fix table for when it goes wrong. The reference
  material it used to carry in full now sits behind links and `<details>`.

### Added

- Spinner widgets in CryTUI, ported from
  [`tui-spinner`](https://github.com/sorinirimies/tui-spinner): `FluxSpinner`
  (a glyph cycling a frame sequence, or a wave when it is more than one cell
  wide), `LinearSpinner`, `SquareSpinner`, `RectSpinner`, `CircleSpinner`, and
  `BarSpinner`, with all 21 frame presets, 16 bar symbol styles, four motions,
  four track styles, and both spin directions. The port was checked frame by
  frame against the crate over the whole matrix of widget, preset, motion,
  spin, size and tick — 65,600 rendered rows, byte-identical — and the golden
  values are pinned in `spec/crytui/spinners_spec.cr`. The ring, circle and bar
  engines fold a long-running tick back into one period, so a dashboard left
  open overnight costs the same per frame as one just started, which the
  stateless originals do not.

  They are used throughout: the splash screen's sweep, wave, and the two rings
  bookending its telemetry block; a wave in the header that only moves while
  the daemon is answering; a glow along the live bar while something is being
  sent out; the searching ring on the daemon-unavailable screen; the turning
  dish on the log panel; and the searching dot in an audio channel with no
  meter reading. The ASCII interface gets the same widgets driven by ASCII
  frame sequences rather than a separate code path.

- Screenshots, rendered rather than photographed. `make readme-shots` draws the
  dashboard, the leader menu, the command line, and the appearance lab with the
  real widget code and serialises each CryTUI buffer to SVG in `docs/assets`, so
  a screenshot cannot show a dashboard the binary no longer produces. The hero
  shot has a light variant, which GitHub serves to readers on a light theme.
  The showcase state behind them is now shared with the microsite's frame
  renderer instead of being duplicated.

## [0.6.0] - 2026-08-02

### Added

- `install.sh`, so obsctl installs in one line:

  ```sh
  curl -fsSL https://worxbend.github.io/obsctl/install.sh | sh
  ```

  It resolves the latest tag, downloads the static build for the machine's
  architecture, and verifies it against the release's `SHA256SUMS.txt` before
  anything is written — a mismatch installs nothing. The binary is run from the
  temporary directory before it is moved into place, so a build that cannot
  execute here never replaces a working one, and the move itself is atomic.
  `--version` and `--dir` (or `OBSCTL_VERSION` and `OBSCTL_INSTALL_DIR`) pin the
  release and the destination; the default is `~/.local/bin`, or
  `/usr/local/bin` when run as root. It needs only curl or wget, tar, and a
  SHA-256 tool.

  The script is deployed to the microsite from the file in this repository
  rather than kept as a second copy, and is attached to every release, so
  `https://github.com/worxbend/obsctl/releases/latest/download/install.sh`
  serves it too. A spec pins the archive names it asks for to the ones the
  release workflow packages — the failure mode is a one-liner that 404s for
  everyone at once.

## [0.5.0] - 2026-08-02

### Added

- Vim keybindings in the TUI, in the AstroNvim arrangement. `Space` is the
  leader and opens a which-key menu of what can follow it — `<leader>f` to find
  a panel, `<leader>u t` for themes, `<leader>o` for reload, dump, and
  reconnect, `<leader>m` for mute, `<leader>q` to quit. `gg` and `G` jump to the
  ends of a panel, `Ctrl-D` and `Ctrl-U` move half of it — measured from the
  panel actually on screen, not a fixed step — and `Ctrl-W` with `h/j/k/l`
  moves between panels. Every sequence lives in one table that both the resolver
  and the menu read, so a binding cannot be dispatchable but unlisted. The
  existing single-letter bindings are untouched.

- `:` as the command line. It opens the palette wearing the key that opened it,
  parses and completes the same commands as `/`, and answers the vim spellings:
  `:q`, `:qa`, `:wq`, `:x` quit and `:h` lists commands. The line is edited with
  the vim command-line keys — `Ctrl-U` clears it back to its leader, `Ctrl-W`
  deletes a word, `Ctrl-N`/`Ctrl-P` cycle completions.

- Mouse control of the rest of the dashboard: which-key entries run or open
  their group on a click, completion chips can be clicked onto the command line
  and cycled with the wheel, a click away from the command line closes it, and
  in the appearance lab a click previews a theme while a second click on it
  persists the choice. The geometry for each of those is a shared layout
  function, so a click resolves against the columns that were actually painted.

- Mouse support in the TUI. Clicking a row focuses and selects it, clicking the
  selected row activates it, and clicking an input's speaker icon toggles its
  mute. The two-step click is deliberate: a stray click cannot cut the program
  scene. Over the audio matrix the wheel is a gain control, acting on whichever
  input the pointer is over without selecting it first; `Shift` and the wheel
  moves through that list instead, and over every other panel the wheel moves
  within it. CryTUI now parses SGR mouse reports (with an X10 fallback) and asks
  for tracking on entry, releasing it before it gives back the alternate screen.

- A microsite at <https://worxbend.github.io/obsctl/>, published from `site/`
  by the `Pages` workflow. The terminal frames on it are not screenshots:
  `scripts/render_site_frames.cr` renders the real widget code into a CryTUI
  buffer and serialises the cells to HTML, and the page restyles itself from
  the same theme palettes it uses to paint them. `make site-frames` regenerates
  them, and the deploy fails if the committed frames are stale.

## [0.4.0] - 2026-08-01

### Added

- A **Stats** pane in the TUI, beside the logs, that appears while the stream is
  live. It reports active FPS with a rolling sparkline, average frame render
  time as a share of the frame budget, and the frames OBS missed to rendering
  lag and skipped to encoding lag, each with its drop ratio. Values are colored
  by severity — under 1% dropped is nominal, 5% or more is critical — and the
  panel summarizes the worst of them as one verdict. It reads the `GetStats`
  sample the daemon already polls, so it adds no OBS traffic, and it gives up
  its column when the terminal is too narrow for both panes.

### Fixed

- A single input with no audio track — an image, colour, or silent browser
  source — no longer stops the daemon from working at all. `GetInputList`
  returns every input, and OBS answers a mute or volume read on a non-audio one
  with "The specified input does not support audio.", which failed the entire
  state snapshot. The supervisor read that as a lost connection and reconnected
  forever, so the daemon never became usable. Inputs whose audio state OBS will
  not report are now left out of the audio matrix instead.
- A failed OBS request is no longer logged as `obs_disconnected`. It logs as
  `obs_request_failed`, so a refused request is not mistaken for a network
  fault.
- Streaming or recording started outside obsctl — from the OBS UI or another
  obs-websocket client — is now reflected in daemon state, so the dashboard
  shows `LIVE` and the CLI reports it. The daemon's Identify mask omitted the
  `Outputs` category, and obs-websocket only delivers an event to clients
  subscribed to its category, so `StreamStateChanged` and `RecordStateChanged`
  never arrived and their handlers never ran. State only looked correct when
  obsctl itself issued the toggle, or after a daemon restart.
- Profile and scene-collection changes made outside obsctl now reach the
  dashboard too. The same missing-category bug applied to `Config` events.
- Output state is also reconciled from the periodic telemetry poll, so it
  converges within one poll interval even if an event is never delivered.

## [0.3.0] - 2026-07-26

### Added

- `obsctl completions bash|zsh|fish` prints a shell completion script generated
  from the command registry, so it always matches the binary. Scene, profile,
  collection, and audio-input names complete from the running daemon via
  `obsctl completions candidates <kind>`, which is bounded by a short timeout
  and stays silent when the daemon is unreachable.
- `--color auto|always|never`. Human output is decorated only when stdout is a
  terminal; `NO_COLOR` and `TERM=dumb` disable it as well.
- `-q`/`--quiet` suppresses human output and leaves the exit code as the only
  signal. `--json` output is unaffected.
- `--timeout SECONDS` bounds a single daemon round trip, reporting
  `REQUEST_TIMEOUT` and exit `3` when it elapses.
- `--help` now lists every command with its usage and summary, not just the
  global options.
- `obsctl version`, `obsctl --version`, and `-V` report the binary version.
  Supports `--json`, which emits the standard envelope with a `version` field.
- A CI workflow that runs formatting, lint, build, and specs on every push to
  `master` and every pull request, against both the declared Crystal floor and
  the latest release.
- `.ameba.yml`, making the lint configuration explicit. Every disabled rule and
  per-path exclusion carries a comment explaining why.
- `make check` runs all four gates; `make format-check` runs the formatter in
  verification mode.
- `LICENSE` (MIT), `CONTRIBUTING.md`, `SECURITY.md`, and this changelog.
- Release builds for `linux-arm64` alongside `linux-amd64`, plus a published
  `SHA256SUMS.txt`.
- `obsctl doctor` reports config, credential, socket, daemon, OBS, and service
  diagnostics with a remedy for every problem it finds. Exits `1` when any
  check fails; warnings alone do not fail it. Supports `--json`.
- Explicit recording controls: `obsctl record start|stop|toggle|pause|resume|status`.
  Bare `obsctl rec` still toggles. `record status` returns structured
  `active`, `paused`, `timecode`, `duration_ms`, and `bytes` fields alongside
  the message, and `stop` reports the written file path.
- `obsctl watch` streams daemon events as newline-delimited JSON, one object
  per line, flushed as written. `--topics` selects a subset of `state`,
  `events`, and `logs`.
- `obsctl config explain` shows every effective setting with the source that
  supplied it; `obsctl config diff` shows only departures from the defaults;
  `obsctl config migrate [--dry-run]` rewrites the file in the current schema,
  dropping unrecognized top-level sections and backing up the original.
- A contract manifest audit that runs in the normal suite, failing when a
  fixture exists on disk without a manifest entry or vice versa, and when an
  entry's category, behavior, or telemetry flag disagrees with reality.

### Changed

- The `claude` and `codex` themes are renamed to `ember` and `slate`. `ember`
  remains the default. Both old ids still resolve to the same palette, so an
  existing `config.yml` keeps working and needs no edit.
- CI lints on the Crystal floor leg only, and the `latest` leg installs with
  `--production`. Ameba analyses source rather than the compiler, so running it
  twice over the same tree added nothing, while its released version (1.6.4)
  does not build on current Crystal — `shards install` failed in postinstall,
  which skipped the build and spec steps and reported a red build for code that
  was fine. The `latest` leg now answers what it exists to answer: does obsctl
  compile and pass its specs on the newest compiler.
- The command set is declared once, in `Domain::CommandRegistry`. The parser,
  the `--json` allowlist, palette completion, `--help`, the palette help text,
  and the generated shell completions all read that declaration. It previously
  lived in six hand-maintained lists that had already drifted apart, and a spec
  now asserts the surfaces agree.
- Commands carry their own IPC name and payload arguments, replacing the two
  type-to-name tables in `CLI::ClientCommands` and the two in `TUI::Dispatcher`.
  The dashboard's two deliberate divergences are declared as such.
- Argument-count errors name the command and show its usage
  (`wrong argument count for scene; usage: scene <scene>`) instead of a bare
  `missing argument`.
- `-h`/`--help` writes to the injected output stream and returns, instead of
  writing to the process stdout and calling `exit 0` from inside the option
  parser.
- `OptionsParser` derives its argv splitting from the same flag declarations it
  builds the parser from, replacing a hand-maintained list of which flags take
  a value.
- Config value types are declared with a single `config_value` field list that
  produces the getters, the YAML mapping, and the initializer. The hand-written
  YAML parsing helpers are gone; the canonical writer is kept deliberately,
  because it defines the on-disk format `obsctl config migrate` converges to.
  Emitted YAML is byte-identical.
- Release binaries are now statically linked against musl, so they no longer
  depend on the host's glibc version.
- `make lint` builds `bin/ameba` from the pinned checkout when it is absent,
  and fails loudly if the checkout itself is missing. It previously printed a
  notice and exited successfully, so the lint gate silently passed on any
  machine without ameba installed.
- Version is `0.3.0`: `shard.yml` still read `0.1.0` when `v0.2.0` was tagged,
  and master has since reintroduced the full TUI.
- `Metrics/CyclomaticComplexity` is enforced at 25 rather than disabled. The
  dispatchers that dominated it were split into named groups and lookup
  tables: `TUI::Input#handle` (was 45), `TUI::Dispatcher#handle` (36),
  `CLI::Main.run` (36), `CommandExecutor#execute_command` (26),
  `Domain::CommandParser#parse` (24), and both `payload_for` mappings (23).
  `CLI::Main.run` is now only an error boundary that delegates to `dispatch`.

### Fixed

- Scene and audio-input names containing a quote or a backslash reach the
  daemon intact. The CLI used to rebuild its already-split arguments into a
  quoted line and re-parse it, which rejected `obsctl scene 'quo"te'` outright
  and silently rewrote `a\ b` to `a b`. Arguments now go straight from argv to
  the parser. Control characters, tabs included, are still refused — that is
  deliberate — but a tab now reports `target must not contain control
  characters` rather than the misleading `wrong argument count`.
- `--json` works for every spelling of a JSON-capable command. `set-scene`,
  `set-profile`, and `set-collection` parsed fine but were rejected by the
  hand-maintained allowlist.
- `obsctl watch | head` exits `0` instead of printing
  `write (...): Broken pipe` and exiting `1`. A closed reader is a normal end
  of stream for a streaming command.
- Human output no longer emits ANSI escapes when stdout is not a terminal, so
  `obsctl status > file` and grep-based scripting see plain text.
- `SIGTERM` and `SIGINT` shut the daemon down in order. Neither was trapped, so
  the default disposition killed the process before `Server#stop` could close
  the OBS WebSocket, log the stop, or remove the socket file — the exact path
  `systemctl --user stop obsctl` takes.
- Socket directories obsctl creates are `0700`. The `/tmp/obsctl-$UID/`
  fallback sits in a world-writable parent and was created at the ambient
  umask. A pre-existing directory owned by another user, writable by others,
  and without the sticky bit is now refused rather than used.
- The three flat contract fixtures at the root of `spec/fixtures/contracts/`
  are canonicalized into `cli/json/` and `ipc/`. Two were exact duplicates of
  existing canonical fixtures; the third, `cli_scene_error.json`, was the only
  unique one and is now `cli/json/scene_error.json` with a manifest entry. The
  fixture root and its manifest agree in both directions again.
- Specs no longer write to the real STDOUT. `Main.run` defaults to the process
  streams, and eleven call sites were taking that default, printing daemon and
  command output between the progress dots.
- The JSON CLI path no longer raises `NilAssertionError` when a daemon returns
  a not-ok response with no error payload; it now raises the protocol error
  that the human-output path already raised.

### Removed

- Six unreachable files: `src/obsctl/support/{result,time,json_helpers}.cr`,
  `src/obsctl/runtime/{event_loop,scheduler}.cr`, and the self-described legacy
  `src/obsctl/cli/command_router.cr`. All but the router were never required by
  anything; the router was required but never instantiated.
- `spec/obsctl/contract/` is merged into `spec/obsctl/contracts/`. Two
  directories a letter apart, with no matching directory under `src/`.
- `PLAN.md` and `scripts/agent-loop.sh`. The script had been dead since the
  Markdown control files it required were deleted, and `PLAN.md` pointed at a
  task queue under the gitignored `.agent-loop/`, so its roadmap was not
  visible to contributors.

## [0.2.0] - 2026-06-28

### Changed

- Made the user service resilient: fixed unit ordering, removed restart limits,
  and allowed startup to survive a missing config file.
- Improved CLI output styling.

### Removed

- TUI mode. (Reintroduced, rewritten on CryTUI, in the unreleased work above.)

## [0.1.0] - 2026-06-24

Initial release: the local daemon, the automation CLI, and config handling.

[Unreleased]: https://github.com/worxbend/obsctl/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/worxbend/obsctl/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/worxbend/obsctl/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/worxbend/obsctl/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/worxbend/obsctl/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/worxbend/obsctl/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/worxbend/obsctl/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/worxbend/obsctl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/worxbend/obsctl/releases/tag/v0.1.0
