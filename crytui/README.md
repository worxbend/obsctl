# CryTUI

An immediate-mode terminal UI library for Crystal, following the narrow
[Ratatui](https://ratatui.rs) architecture rather than its Rust syntax.

Immediate mode means you do not build a tree of widget objects and mutate it.
Every frame, you draw the whole screen from your own application state into a
`Buffer` — a grid of styled cells. CryTUI compares that buffer against the one
from the previous frame and writes only the cells that actually changed, so a
full redraw costs about as much as the difference between two frames.

```
your application state
          |
          v
    your widgets  ->  CryTUI::Frame  ->  CryTUI::Buffer
                                              |
                                        cell-level diff
                                              |
                                   ANSI backend / TestBackend
```

## What is in the box

- **Geometry** — rectangles, clipping, and a constraint solver for nested
  layouts (fixed, minimum, maximum, percentage and ratio constraints).
- **Buffer and diff** — Unicode-grapheme-aware cells, so a double-width glyph
  occupies the two columns it actually paints and is never drawn in half.
- **Styles** — 16-colour, 256-colour and true-colour foregrounds and
  backgrounds, plus modifiers (bold, dim, italic, underline, reverse).
- **Terminal** — raw-mode entry and exit, alternate screen, cursor hiding, and
  restoration on signals so a crash cannot leave the terminal unusable.
- **Input** — an incremental VT parser covering keys, modifiers, arrow and
  function keys, bracketed paste, and mouse events.
- **Widgets** — blocks and borders, paragraphs with wrapping, lists, gauges,
  tables and sparklines.
- **Spinners** — several animated progress indicators.

## Usage

Add it to your `shard.yml`:

```yaml
dependencies:
  crytui:
    path: ../obsctl/crytui
```

Then:

```crystal
require "crytui"

backend = CryTUI::AnsiBackend.for_terminal(STDOUT, STDIN)
terminal = CryTUI::Terminal.new(backend)

terminal.run(STDIN) do |t|
  parser = CryTUI::InputParser.new
  quit = false
  until quit
    t.draw do |frame|
      CryTUI::Widgets::Paragraph.new(
        "hello — press q to quit",
        block: CryTUI::Widgets::Block.new(title: " demo ")
      ).render(frame.area, frame.buffer)
    end
    parser.feed(STDIN.read_char.to_s).each do |event|
      quit = true if event.is_a?(CryTUI::KeyEvent) && event.character == 'q'
    end
  end
end
```

Widgets do not draw themselves: each one exposes `render(area, buffer)` and
paints into the frame's buffer, which CryTUI diffs against the previous frame.

## Status

CryTUI lives in the [obsctl](https://github.com/worxbend/obsctl) repository as
its own shard. It is developed against obsctl's dashboard, which is currently
its only consumer, so the API is shaped by that one use and may still change.
It depends on nothing from obsctl, and its specs run on their own:

```sh
cd crytui && shards install && crystal spec
```

## License

MIT. See [LICENSE](LICENSE).
