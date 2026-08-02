require "../keymap"
require "../layout"
require "./chrome"

module Obsctl
  module TUI
    module Widgets
      # The menu that opens while a key sequence is half typed, listing what can
      # be pressed next. It is drawn last so it floats over the dashboard, and
      # it clears its own cells first because an overlay inherits whatever the
      # panels underneath already painted.
      module WhichKey
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          return if model.pending_sequence.empty?

          entries = Keymap.continuations(model.pending_sequence)
          rect = WhichKeyLayout.compute(area, entries, DashboardLayout.compute(area, model.streaming?).palette)
          return if rect.empty?

          theme = model.theme
          clear(rect, buffer, theme)
          block = CryTUI::Widgets::Block.new(
            title: " #{model.symbol("⌨", "keys")} #{Keymap.title(model.pending_sequence)} ",
            style: CryTUI::Style.new(background: theme.background, foreground: theme.foreground),
            border_style: CryTUI::Style.new(foreground: theme.border_focus),
            border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII
          )
          lines = WhichKeyLayout.visible(entries, rect).map { |entry| entry_line(entry, model) }
          CryTUI::Widgets::StyledText.new(lines, block: block).render(rect, buffer)
        end

        private def clear(rect : CryTUI::Rect, buffer : CryTUI::Buffer, theme : Theme)
          style = CryTUI::Style.new(background: theme.background, foreground: theme.foreground)
          blank = " " * rect.width
          (rect.y...rect.bottom).each { |row| buffer.set_string(rect.x, row, blank, style) }
        end

        # Split so the spans concatenate back to `WhichKeyLayout.entry_text`,
        # which is what the panel was measured and hit-tested against.
        private def entry_line(entry : Keymap::Entry, model : Model) : CryTUI::Line
          theme = model.theme
          label_style = entry.group ? CryTUI::Style.new(foreground: theme.accent_alt) : CryTUI::Style.new(foreground: theme.foreground)
          CryTUI::Line.new([
            CryTUI::Span.new(" #{entry.token}", CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new("  ", CryTUI::Style.new(foreground: theme.muted)),
            CryTUI::Span.new("#{entry.group ? "+" : ""}#{entry.label} ", label_style),
          ])
        end
      end
    end
  end
end
