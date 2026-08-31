require "../layout"
require "../overlay_layout"
require "../scene_profiles"
require "./chrome"

module Obsctl
  module TUI
    module Widgets
      # The overlay `<leader>P` opens: every scene the daemon reported, with the
      # ones the draft hides drawn dimmed.
      #
      # This is the one surface that lists hidden scenes, because it is the one
      # surface that can bring them back; everything else in the dashboard
      # reads the filtered `Model#scenes`.
      #
      # Drawn after the dashboard so it floats above it, and it blanks its own
      # cells first because an overlay otherwise inherits whatever the panels
      # underneath already painted.
      module SceneProfiles
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          return unless model.scene_profile_editor.active

          scenes = model.all_scenes
          rect = SceneProfilesLayout.compute(area, model)
          return if rect.empty?

          theme = model.theme
          clear(rect, buffer, theme)
          frame = block(model, rect)
          frame.render(rect, buffer)
          items = scenes.map { |scene| item(scene, model) }
          state = CryTUI::Widgets::ListState.new(selected: model.scene_profile_editor.cursor)
          highlight = CryTUI::Style.new(
            foreground: theme.highlight_foreground,
            background: theme.highlight_background,
            modifiers: CryTUI::Modifier::Bold
          )
          # The block is drawn here rather than handed to the list, because the
          # list gets only the rows above the hint row and the border is around
          # both of them.
          CryTUI::Widgets::List.new(items, highlight_style: highlight)
            .render(frame.inner(SceneProfilesLayout.list_area(rect)), buffer, state)
          render_hints(rect, frame.inner(rect), buffer, model)
        end

        # The keys, on the last row inside the border. They are not in the
        # title because the title carries the profile's name, and a name of any
        # length would push them off the end of the line -- taking the way out
        # of the modal with them.
        private def render_hints(rect : CryTUI::Rect, inner : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          return if inner.height <= 0

          style = CryTUI::Style.new(foreground: model.theme.muted, background: model.theme.background)
          text = CryTUI::TextWidth.truncate(SceneProfilesLayout.hint_text(model, rect.width), inner.width, model.symbol("…", "~"))
          buffer.set_string(inner.x, SceneProfilesLayout.hint_row(rect), text, style, inner.width)
        end

        # Built here rather than through `Chrome.panel` because a dashboard
        # panel is transparent and an overlay must not be: the box needs an
        # opaque `style` so the dashboard does not show through its padding.
        private def block(model : Model, rect : CryTUI::Rect) : CryTUI::Widgets::Block
          theme = model.theme
          # Through the shared layout, and against the width the box actually
          # got, so the title drawn is the title that fits the box.
          heading, name = SceneProfilesLayout.title_parts(model, rect.width)
          title = CryTUI::Line.new([
            CryTUI::Span.new(heading, CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new(name, CryTUI::Style.new(foreground: theme.badge_foreground, background: theme.badge_background, modifiers: CryTUI::Modifier::Bold)),
          ])
          CryTUI::Widgets::Block.new(
            title: title,
            style: CryTUI::Style.new(background: theme.background, foreground: theme.foreground),
            border_style: CryTUI::Style.new(foreground: theme.border_focus),
            border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII
          )
        end

        private def clear(rect : CryTUI::Rect, buffer : CryTUI::Buffer, theme : Theme)
          style = CryTUI::Style.new(background: theme.background, foreground: theme.foreground)
          blank = " " * rect.width
          (rect.y...rect.bottom).each { |row| buffer.set_string(rect.x, row, blank, style) }
        end

        # Split so the spans concatenate back to `SceneProfilesLayout.row_text`,
        # which is what the box was measured and hit-tested against.
        private def item(scene : OBS::State::SceneState, model : Model) : CryTUI::Widgets::ListItem
          theme = model.theme
          hidden = model.scene_profile_editor.hidden.includes?(scene.name)
          # `Dim` as well as the muted colour: the selection bar re-tints a span
          # whose own colour cannot be read against it (see `ForegroundGuard`),
          # so a hidden row under the cursor would otherwise lose the only
          # styling that marks it hidden.
          dim = CryTUI::Style.new(foreground: theme.muted, modifiers: CryTUI::Modifier::Dim)
          marker_style = hidden ? dim : CryTUI::Style.new(foreground: theme.success)
          name_style = hidden ? dim : CryTUI::Style.new(foreground: scene.active ? theme.success : theme.foreground)
          line = CryTUI::Line.new([
            CryTUI::Span.new(" #{SceneProfilesLayout.marker(model, hidden)}", marker_style),
            CryTUI::Span.new("  ", CryTUI::Style.new(foreground: theme.muted)),
            CryTUI::Span.new("#{scene.name} ", name_style),
          ])
          CryTUI::Widgets::ListItem.new([line])
        end
      end
    end
  end
end
