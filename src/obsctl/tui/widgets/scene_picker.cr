require "../layout"
require "../overlay_layout"
require "../scene_picker"
require "./overlay"

module Obsctl
  module TUI
    module Widgets
      # The overlay `<leader>s` opens: every scene beside the single key that
      # switches to it.
      #
      # Drawn after the dashboard so it floats above it, and it blanks its own
      # cells first because an overlay otherwise inherits whatever the panels
      # underneath already painted.
      module ScenePicker
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          return unless model.scene_picker_active

          entries = model.scene_picker_entries
          rect = ScenePickerLayout.compute(area, model)
          return if rect.empty?

          theme = model.theme
          Overlay.clear(rect, buffer, theme)
          items = entries.map { |entry| item(entry, model) }
          state = CryTUI::Widgets::ListState.new(selected: model.scene_picker_cursor)
          CryTUI::Widgets::List.new(items, highlight_style: Overlay.highlight_style(theme), block: block(entries.size, model)).render(rect, buffer, state)
        end

        private def block(count : Int32, model : Model) : CryTUI::Widgets::Block
          theme = model.theme
          # Through the shared layout, so the title drawn is the title the box
          # was sized around.
          heading, badge, hint = ScenePickerLayout.title_parts(model, count)
          title = CryTUI::Line.new([
            CryTUI::Span.new(heading, CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new(badge, CryTUI::Style.new(foreground: theme.badge_foreground, background: theme.badge_background, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new(hint, CryTUI::Style.new(foreground: theme.muted)),
          ])
          Overlay.block(model, title)
        end

        # Split so the spans concatenate back to `ScenePickerLayout.row_text`,
        # which is what the box was measured and hit-tested against.
        #
        # The live scene is marked by colouring its name rather than by adding
        # a marker character, so every row stays exactly as wide as it measured.
        private def item(entry : TUI::ScenePicker::Entry, model : Model) : CryTUI::Widgets::ListItem
          theme = model.theme
          label = entry.label
          label_style = label ? CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new(foreground: theme.muted)
          name_style = CryTUI::Style.new(foreground: entry.scene.active ? theme.success : theme.foreground)
          line = CryTUI::Line.new([
            CryTUI::Span.new(" #{label || ' '}", label_style),
            CryTUI::Span.new("  ", CryTUI::Style.new(foreground: theme.muted)),
            CryTUI::Span.new("#{entry.scene.name} ", name_style),
          ])
          CryTUI::Widgets::ListItem.new([line], entry.scene.active ? CryTUI::Style.new(modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new)
        end
      end
    end
  end
end
