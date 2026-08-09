# Demo recording

`obsctl.cast` is the source of truth for what obsctl looks like: an
[asciinema](https://asciinema.org) recording of a real `obsctl tui` session, 112x57,
~89s, in **asciicast v3** format.

It is consumed two ways:

- **The microsite** plays the cast itself, through the player vendored in `site/vendor/`.
  Text, not video — crisp at any size, scrubbable, and you can select and copy straight
  out of it. The Pages workflow copies this file into `site/demo/` at deploy time, so the
  repository holds exactly one copy of it.
- **The README** embeds `obsctl.gif`, because GitHub cannot play a cast inline.

This replaced the rendered screenshots the README and the site used to carry. A still
frame goes stale the moment a panel is redrawn, and nothing catches it; a cast is
re-recorded from the code it documents, and every panel in it is animating, which is half
of what the dashboard actually is.

## Recording

The cast committed here is **trimmed to the obsctl session itself** — no shell prompt, no
`shards build` scrollback, no return to the prompt at the end. A raw recording has all
three, and the site plays the cast unedited, so a visitor would otherwise sit through
half a minute of build output before anything happened.

Record however you like:

```sh
asciinema rec raw.cast     # then run `obsctl tui`, drive it, quit, exit the shell
```

Then trim to the frame where the TUI takes over the screen. The TUI switches the terminal
to its alternate screen buffer on start (`\x1b[?1049h`) and switches back on quit
(`\x1b[?1049l`), which makes both ends easy to find mechanically — dump the event indices
first:

```sh
python3 - <<'EOF'
import json
with open("raw.cast") as fh:
    fh.readline()                      # header
    events = [json.loads(l) for l in fh if l.strip()]
# asciicast v3 stores the gap since the previous event, not an absolute time.
t = 0.0
for i, e in enumerate(events):
    t += e[0]
    if "\x1b[?1049h" in e[2]: print(round(t, 3), i, "ENTER ALT SCREEN")
    if "\x1b[?1049l" in e[2]: print(round(t, 3), i, "LEAVE ALT SCREEN")
EOF
```

Keep the enter event and everything up to (but not including) the leave event:

```sh
python3 - <<'EOF'
import json
START, END = 39, 113599             # the two indices printed above
with open("raw.cast") as fh:
    header = fh.readline()
    events = [json.loads(l) for l in fh if l.strip()]
kept = []
for e in events[START:END]:
    # The first kept event opens the timeline, so its gap resets to zero.
    kept.append([0.0 if not kept else e[0], e[1], e[2]])
with open("obsctl.cast", "w") as fh:
    fh.write(header)
    for e in kept:
        fh.write(json.dumps([round(e[0], 6), e[1], e[2]], ensure_ascii=False) + "\n")
EOF
```

## Regenerating the GIF

`agg` only reads asciicast v2, so convert first. No trimming step is needed — the cast is
already trimmed.

```sh
cargo install --locked --git https://github.com/asciinema/agg   # provides `agg`

asciinema convert -f asciicast-v2 --overwrite obsctl.cast /tmp/v2.cast
agg --font-size 11 --fps-cap 8 --speed 2.0 --idle-time-limit 1 \
    --last-frame-duration 3 /tmp/v2.cast obsctl.gif
```

That lands near 1.6 MB at 772x893, which renders roughly 1:1 in GitHub's README column, so
the text stays sharp without scaling. `--speed 2.0` brings the 89-second session down to
about 35 seconds of playback, which is as long as a README embed can hold attention.

Size is dominated by how much of the screen changes between frames, and the dashboard
animates almost everywhere — gradient chrome, spinners, sparklines, and the audio meters.
Raising `--font-size` or `--fps-cap` therefore grows the file fast; dropping `--fps-cap`
to 6 saves a few hundred kilobytes but visibly stutters the spinners. If you re-record at
a different terminal size, re-check the output width and update the `width` attribute on
the README's `<img>` so it keeps rendering 1:1.
