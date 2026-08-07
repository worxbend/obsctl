#!/usr/bin/env crystal
#
# Renders the README's screenshots into docs/assets/*.svg.
#
# They are not photographs of a terminal: each one is the real widget code
# drawn into a CryTUI buffer and serialised cell by cell, so a screenshot
# cannot show a dashboard the binary no longer produces. Run
# `make readme-shots` after changing a widget or a theme.

require "./support/showcase"
require "../src/obsctl/tui/widgets/settings"
require "../src/obsctl/tui/widgets/which_key"

module ReadmeShots
  extend self

  # Cell metrics. A monospace advance is 0.6em at every size worth using, and
  # every run is drawn with `textLength`, so the grid holds even when the
  # viewer has none of the preferred fonts.
  FONT_SIZE   = 15.0
  CELL_WIDTH  =  9.0
  CELL_HEIGHT = 19.0
  BASELINE    = 14.0
  PADDING     = 16.0
  CHROME      = 34.0

  FONT_STACK = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'DejaVu Sans Mono', monospace"

  record Shot,
    name : String,
    title : String,
    width : Int32,
    height : Int32,
    themes : Array(String),
    build : Proc(Obsctl::TUI::Model, CryTUI::Rect, CryTUI::Buffer, Nil)

  # The hero shot carries a light variant so the README can serve one to each
  # GitHub colour scheme; the rest are dark only, which is how a terminal is
  # usually looked at anyway.
  DARK  = "ember"
  LIGHT = "github-light"

  SHOTS = [
    Shot.new("dashboard", "obsctl — live", 100, 30, [DARK, LIGHT], ->(model : Obsctl::TUI::Model, area : CryTUI::Rect, buffer : CryTUI::Buffer) {
      Obsctl::TUI::Widgets::Dashboard.render(area, buffer, model)
    }),
    Shot.new("which-key", "obsctl — the leader menu", 100, 30, [DARK], ->(model : Obsctl::TUI::Model, area : CryTUI::Rect, buffer : CryTUI::Buffer) {
      model.pending_sequence = "<leader>"
      Obsctl::TUI::Widgets::Dashboard.render(area, buffer, model)
      Obsctl::TUI::Widgets::WhichKey.render(area, buffer, model)
    }),
    Shot.new("command-line", "obsctl — the command line", 100, 30, [DARK], ->(model : Obsctl::TUI::Model, area : CryTUI::Rect, buffer : CryTUI::Buffer) {
      palette = model.command_palette
      palette.active = true
      palette.input = ":scene "
      palette.completions = [":scene BRB", ":scene Guest Cam", ":scene Main Camera", ":scene Screen Share"]
      palette.completion_index = 2
      model.set_last_result("scene set: Main Camera")
      model.anim.frame = 40_u64
      Obsctl::TUI::Widgets::Dashboard.render(area, buffer, model)
    }),
    Shot.new("themes", "obsctl — the appearance lab", 100, 26, [DARK], ->(model : Obsctl::TUI::Model, area : CryTUI::Rect, buffer : CryTUI::Buffer) {
      model.view = Obsctl::TUI::View::Settings
      model.settings_cursor = Obsctl::TUI::Theme::ALL.index { |theme| theme.id == model.theme.id } || 0
      Obsctl::TUI::Widgets::Settings.render(area, buffer, model)
    }),
  ]

  def run : Nil
    directory = File.expand_path("../docs/assets", __DIR__)
    Dir.mkdir_p(directory)

    SHOTS.each do |shot|
      shot.themes.each do |theme_id|
        theme = Obsctl::TUI::Theme.by_id(theme_id)
        model = Showcase.model(theme)
        buffer = CryTUI::Buffer.new(CryTUI::Rect.new(0, 0, shot.width, shot.height))
        shot.build.call(model, buffer.area, buffer)

        suffix = shot.themes.size > 1 && theme_id == LIGHT ? "-light" : ""
        path = File.join(directory, "shot-#{shot.name}#{suffix}.svg")
        File.write(path, svg(buffer, theme, shot.title))
        STDOUT.puts "wrote #{path} (#{shot.width}x#{shot.height}, #{theme.label})"
      end
    end
  end

  private def svg(buffer : CryTUI::Buffer, theme : Obsctl::TUI::Theme, title : String) : String
    ground = Showcase.swatch(theme.background, "#101010")
    muted = Showcase.swatch(theme.muted, "#8a867d")
    border = Showcase.swatch(theme.border, "#4a4640")
    width = buffer.area.width * CELL_WIDTH + PADDING * 2
    height = buffer.area.height * CELL_HEIGHT + PADDING * 2 + CHROME

    String.build do |io|
      io << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{fmt(width)}" height="#{fmt(height)}" )
      io << %(viewBox="0 0 #{fmt(width)} #{fmt(height)}" font-family="#{FONT_STACK}" font-size="#{fmt(FONT_SIZE)}">\n)
      io << %(<rect x="0" y="0" width="#{fmt(width)}" height="#{fmt(height)}" rx="12" fill="#{ground}" stroke="#{border}"/>\n)

      # A window bar, so a screenshot reads as an application rather than as a
      # slab of text pasted into the page.
      io << %(<g>\n)
      {"#ff5f57", "#febc2e", "#28c840"}.each_with_index do |colour, index|
        io << %(<circle cx="#{fmt(PADDING + 6 + index * 18)}" cy="#{fmt(CHROME / 2)}" r="6" fill="#{colour}"/>\n)
      end
      io << %(<text x="#{fmt(width / 2)}" y="#{fmt(CHROME / 2 + 4)}" fill="#{muted}" font-size="#{fmt(FONT_SIZE - 2)}" text-anchor="middle">)
      io << Showcase.escape(title) << "</text>\n"
      io << %(<line x1="0" y1="#{fmt(CHROME)}" x2="#{fmt(width)}" y2="#{fmt(CHROME)}" stroke="#{border}" stroke-opacity="0.6"/>\n)
      io << "</g>\n"

      backgrounds = String::Builder.new
      glyphs = String::Builder.new
      (0...buffer.area.height).each { |row| emit_row(buffer, row, ground, backgrounds, glyphs) }

      io << backgrounds.to_s
      io << glyphs.to_s
      io << "</svg>\n"
    end
  end

  # One row, as background rectangles under one text run per style change.
  # Runs are batched rather than emitted per cell because a 100x30 frame is
  # 3,000 cells, and a file that large would dominate the repository.
  private def emit_row(buffer : CryTUI::Buffer, row : Int32, ground : String, backgrounds : String::Builder, glyphs : String::Builder) : Nil
    y = CHROME + PADDING + row * CELL_HEIGHT
    text = String::Builder.new
    style = nil.as(CryTUI::Style?)
    start = 0
    cells = 0

    flush = -> do
      content = text.to_s
      unless content.blank? && style.try { |value| background_of(value) }.nil?
        emit_run(content, style, start, cells, y, ground, backgrounds, glyphs)
      end
      text = String::Builder.new
      cells = 0
    end

    column = 0
    while column < buffer.area.width
      cell = buffer[buffer.area.x + column, buffer.area.y + row]
      if cell.continuation?
        column += 1
        next
      end

      current = cell.style
      if cells > 0 && !same_style?(current, style)
        flush.call
        start = column
      end
      start = column if cells == 0
      style = current
      symbol = cell.symbol.empty? ? " " : cell.symbol
      text << symbol
      cells += {CryTUI::TextWidth.width(symbol), 1}.max
      column += 1
    end
    flush.call
  end

  private def emit_run(content : String, style : CryTUI::Style?, start : Int32, cells : Int32, y : Float64, ground : String, backgrounds : String::Builder, glyphs : String::Builder) : Nil
    return if cells == 0

    x = PADDING + start * CELL_WIDTH
    span = cells * CELL_WIDTH
    resolved = style || CryTUI::Style.new
    foreground, background = resolve(resolved)

    if background && background != ground
      backgrounds << %(<rect x="#{fmt(x)}" y="#{fmt(y)}" width="#{fmt(span)}" height="#{fmt(CELL_HEIGHT)}" fill="#{background}"/>\n)
    end
    return if content.blank?

    glyphs << %(<text x="#{fmt(x)}" y="#{fmt(y + BASELINE)}" textLength="#{fmt(span)}" lengthAdjust="spacingAndGlyphs" xml:space="preserve")
    glyphs << %( fill="#{foreground}") if foreground
    glyphs << %( font-weight="700") if resolved.modifiers.bold?
    glyphs << %( font-style="italic") if resolved.modifiers.italic?
    glyphs << %( text-decoration="underline") if resolved.modifiers.underlined?
    glyphs << %( opacity="0.65") if resolved.modifiers.dim?
    glyphs << '>' << Showcase.escape(content) << "</text>\n"
  end

  private def resolve(style : CryTUI::Style) : Tuple(String?, String?)
    foreground = style.foreground
    background = style.background
    foreground, background = background, foreground if style.modifiers.reversed?
    {foreground.try { |value| Showcase.css_color(value) }, background.try { |value| Showcase.css_color(value) }}
  end

  private def background_of(style : CryTUI::Style) : CryTUI::Color?
    style.modifiers.reversed? ? style.foreground : style.background
  end

  private def same_style?(current : CryTUI::Style, previous : CryTUI::Style?) : Bool
    return false unless previous

    current.foreground == previous.foreground &&
      current.background == previous.background &&
      current.modifiers == previous.modifiers
  end

  # Trims the trailing zeroes an SVG does not need, so the files diff cleanly.
  private def fmt(value : Float64) : String
    value == value.round ? value.to_i.to_s : value.round(2).to_s
  end
end

ReadmeShots.run
