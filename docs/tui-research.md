# TUI Research and CryTUI Direction

This document records the implementation research for porting the `obsctl-rs`
dashboard to Crystal. The Rust checkout at `../obsctl-rs` is the behavioral
reference. Its TUI currently contains roughly 6,600 lines across the model,
session, input, layout, animation, theme, widgets, and rendering/session tests.

## Required Ratatui Subset

`obsctl-rs` pins Ratatui 0.29. The application does not need a complete Ratatui
clone. It needs these capabilities:

1. immediate-mode rendering into a rectangular cell buffer;
2. cell symbols plus independent foreground/background/modifier styles;
3. nested horizontal and vertical constraint layouts;
4. clipping and Unicode-aware text placement;
5. blocks, paragraphs, lists, gauges, sparklines, and stateful selection;
6. a double-buffered terminal that emits only changed cells;
7. a deterministic memory backend for widget and full-frame specs;
8. raw terminal lifecycle, resize, keyboard, paste, and mouse events;
9. safe restoration of the terminal after normal exit, errors, and signals.

The important Ratatui architectural boundary is that widgets only render into a
`Buffer`. A `Terminal` owns current/previous buffers and a backend performs real
I/O. Input and application event-loop policy remain outside the rendering core.
That boundary maps well to Crystal fibers and to obsctl's existing IPC session.

## Existing Crystal Libraries

### Crysterm

Repository: <https://github.com/crystallabs/crysterm>

Crysterm is active and unusually comprehensive (the inspected 2026-07-15
revision contains about 75,000 lines of Crystal). It provides terminfo-backed
terminal I/O, input protocols, Unicode helpers, event routing, layout, a large
retained widget hierarchy, rich styling, images, mouse support, and careful
terminal teardown. Its device/input work is valuable prior art.

It is not a drop-in backbone for this project:

- Crysterm is AGPL-3.0 while obsctl is MIT. Copying, modifying, statically
  linking, or vendoring it would change distribution obligations. A fork is
  viable only if the project intentionally adopts AGPL-compatible terms or the
  copyright holder grants a compatible license.
- Its retained, Qt/Blessed-inspired object tree is substantially different from
  Ratatui's small immediate-mode buffer API used by `obsctl-rs`.
- Its broad dependency and feature surface is much larger than obsctl needs.

Decision: do not fork or copy Crysterm under the current MIT project terms.
Continue to study its public behavior and terminal lifecycle, especially
terminfo, enhanced keyboard protocols, resize, mouse handling, and best-effort
restoration. A future optional adapter can be considered without making obsctl
widgets depend on Crysterm's retained widget model.

### dsisnero/terminal

Repository: <https://github.com/dsisnero/terminal>

This smaller library is architecturally closer: it has a screen buffer, diff
renderer, raw Unix/Windows input, fibers/channels, layout constraints, and an
MIT declaration in its README. However, the inspected 2025-11-09 revision is
version 0.1.0, its shard manifest has the license commented out, its diff is
row-level rather than cell-level, and its Unix input source explicitly leaves
arrow/function-key and robust UTF-8 parsing for later. It is useful prior art
but not yet a sufficiently strong foundation for obsctl's reference behavior.

Decision: keep it in the comparison set and re-evaluate individual low-level
pieces. Do not introduce it as an application dependency until its license
metadata, input coverage, and compatibility gates are resolved.

## CryTUI Architecture

`src/crytui` is an in-tree incubation library with a clean extraction path to a
standalone shard. Its API follows the narrow Ratatui architecture rather than
the Rust syntax:

```text
obsctl TUI model + IPC events
          |
          v
obsctl widgets -> CryTUI Frame -> CryTUI Buffer
                                      |
                             cell-level diff
                                      |
                         ANSI backend / TestBackend
```

The implementation now includes rectangles and clipping, constraints and nested
layout, colors/styles/modifiers, Unicode-grapheme-aware cells and buffers,
wide-cell continuation tracking, cell-level diffing, an immediate-mode
terminal/frame, memory and ANSI backends, exception-safe output restoration, an
incremental VT key/paste parser, and initial block, paragraph, gauge, and
sparkline widgets. Raw-mode ownership uses Crystal's exact termios save/restore
block, while live ioctl sizing and resize polling feed the backend. A real PTY
integration probe verifies discovery, resize, and exception-path restoration.

The first obsctl layer above CryTUI is also present: a port of the Rust panel
model and event applier consumes only local IPC state/log/event messages. It
does not import or instantiate the OBS client. This establishes the required
thin-client boundary before widget rendering is ported.

The first application-driven widget expansion is now implemented. CryTUI has
styled spans/lines, Unicode-aware alignment, scrollable variable-height lists,
stateful selection, full-row highlights, and ASCII/rounded/thick/double border
sets. obsctl uses those primitives for its header, scenes, logarithmic audio
meters, connection/unavailable screens, and command palette. Direct buffer
specs cover connected, disconnected, selected, empty, metered, and completion
states. The complete 29-theme Rust reference catalog is available, along with
partial custom RGB palettes whose missing or invalid fields safely inherit the
Claude defaults. Runtime refresh timing, icon use, advanced rendering, and
theme selection now come from the typed `ui` configuration.

The secondary Rust surfaces are also ported. The appearance lab uses the same
45/55 theme-list and semantic-preview composition, Enter persists the chosen
theme atomically without discarding other UI settings, and startup renders a
responsive animated splash that can be dismissed by any key before the daemon
connection begins. Shared pulse, spinner, RGB blend, gradient, Unicode
sparkline, and ASCII history helpers live outside the widgets for reuse. The
standalone grouped Scene Map widget is available as in the Rust source, though
the reference dashboard itself does not currently mount it.

Ratatui 0.29 delegates layout to a strength-ranked Cassowary solver rather
than a greedy splitter. CryTUI now follows that architecture using the MIT
licensed `kiwi.cr` Cassowary port (pinned through `shard.lock`) for mixed
constraints, with deterministic cumulative rounding for homogeneous ratios,
percentages, and weighted fills. Differential probes against Ratatui cover
normal, undersized, weighted, and spaced allocations. Equal-strength solutions
can differ between Cassowary implementations where Ratatui itself has no
stable/fair tie contract; required bounds and documented constraint priorities
remain identical.

The primary dashboard now renders as a single frame using the same nested area
contract as the Rust reference: fixed header/live/log/palette chrome, a flexible
scenes/audio row, and a smaller profiles/collections row. The complete frame
includes daemon logs and LIVE/REC placeholders sourced from IPC state. The
background-fill exercise also exposed and fixed an important buffer semantic:
writing a symbol patches the cell style instead of discarding an already
painted background, matching Ratatui's layered rendering behavior.

The runtime path is now executable rather than only renderable. `obsctl` and
`obsctl tui` create a raw CryTUI terminal, establish a persistent local IPC
subscription, apply pushed events, send correlated commands over short-lived
connections, and restore the terminal on quit. A PTY end-to-end spec launches
the real Crystal entrypoint against a fake Unix-socket daemon, verifies the
three-topic subscription, supplies `q`, observes the subscription close, and
asserts alternate-screen/cursor restoration sequences.

The daemon snapshot now carries the Rust model's studio and telemetry state:
profile names/current profile, scene collections/current collection, OBS
CPU/memory/disk/FPS/frame statistics, and active stream/record durations.
Profile and collection selection are real server-owned OBS commands rather
than client-only compatibility fields. The Crystal supervisor now mirrors the
Rust two-second telemetry poll and derives bitrate from consecutive active
`outputBytes` samples, resetting its baseline across stopped/restarted streams.
The live bar consumes that snapshot directly, including formatted LIVE/REC
timers, CPU/FPS/memory values, bitrate, and Unicode or ASCII history graphs.
Scene `hidden` metadata also survives config parsing/dumps and authoritative
snapshots; hidden utility scenes remain addressable but are omitted from TUI
navigation just like the Rust model.

## Delivery Sequence

1. Harden core geometry, Unicode display width, layout allocation, styled text,
   and widget-state primitives with direct buffer specs.
2. Add ANSI/capability backend, raw-mode guard, key parser, resize handling, and
   PTY lifecycle tests. Terminal restoration is a release gate.
3. Port the `obsctl-rs` TUI model, event applier, completion, input actions, and
   layout without OBS access in the client.
4. Port dashboard widgets in observable slices using the Rust TestBackend tests
   as behavioral contracts.
5. Wire `obsctl` and `obsctl tui` to the existing Unix IPC subscription and
   command paths, including server-unavailable actions.
6. Run full Crystal gates plus PTY smoke tests and compare reference screenshots
   at representative terminal sizes and ASCII/Unicode modes.

## Sources

- Ratatui 0.29 documentation: <https://docs.rs/crate/ratatui/0.29.0>
- Ratatui rendering internals: <https://ratatui.rs/concepts/rendering/under-the-hood/>
- Ratatui layout concepts: <https://ratatui.rs/concepts/layout/>
- Crysterm source and documentation: <https://github.com/crystallabs/crysterm>
- Terminal source and documentation: <https://github.com/dsisnero/terminal>
