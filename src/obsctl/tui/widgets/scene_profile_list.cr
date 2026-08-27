require "../layout"
require "../scene_profile_list"
require "./chrome"

module Obsctl
  module TUI
    module Widgets
      # The overlay `<leader>p` opens: "show every scene" first, then every
      # saved profile, with the one in effect marked.
      #
      # This is where a profile is chosen, switched and managed; the editor
      # behind `<leader>P` is where one is built. Keeping them apart is what
      # lets Enter mean one thing in each -- "put this in effect" here, "save
      # this draft" there.
      #
      # Drawn after the dashboard so it floats above it, and it blanks its own
      # cells first because an overlay otherwise inherits whatever the panels
      # underneath already painted.
      module SceneProfileList
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          return unless model.scene_profile_list.active

          entries = model.scene_profile_list_entries
          rect = SceneProfileListLayout.compute(area, model)
          return if rect.empty?

          theme = model.theme
          clear(rect, buffer, theme)
          frame = block(model, entries.size)
          frame.render(rect, buffer)
          items = entries.map { |entry| item(entry, model) }
          state = CryTUI::Widgets::ListState.new(selected: model.scene_profile_list.cursor)
          highlight = CryTUI::Style.new(
            foreground: theme.highlight_foreground,
            background: theme.highlight_background,
            modifiers: CryTUI::Modifier::Bold
          )
          # The block is drawn here rather than handed to the list, because the
          # list gets only the rows above the hint row and the border is around
          # both of them.
          CryTUI::Widgets::List.new(items, highlight_style: highlight)
            .render(frame.inner(SceneProfileListLayout.list_area(rect)), buffer, state)
          render_hints(rect, frame.inner(rect), buffer, model)
        end

        # The keys, on the last row inside the border, the same place the
        # editor keeps its own.
        #
        # An armed delete is drawn in the warning colour rather than the muted
        # one: the row's text is the only thing that changes when the first `d`
        # lands, and a reader who is looking at the rows rather than at the
        # hints has to be able to tell from the corner of their eye that the
        # next keystroke is the destructive one.
        private def render_hints(rect : CryTUI::Rect, inner : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          return if inner.height <= 0

          theme = model.theme
          colour = model.scene_profile_list.confirming ? theme.warning : theme.muted
          style = CryTUI::Style.new(foreground: colour, background: theme.background)
          text = CryTUI::TextWidth.truncate(SceneProfileListLayout.hint_text(model, rect.width), inner.width, model.symbol("…", "~"))
          buffer.set_string(inner.x, SceneProfileListLayout.hint_row(rect), text, style, inner.width)
        end

        # Built here rather than through `Chrome.panel` because a dashboard
        # panel is transparent and an overlay must not be: the box needs an
        # opaque `style` so the dashboard does not show through its padding.
        private def block(model : Model, count : Int32) : CryTUI::Widgets::Block
          theme = model.theme
          # Through the shared layout, so the title drawn is the title the box
          # was sized around.
          heading, badge, hint = SceneProfileListLayout.title_parts(model, count)
          title = CryTUI::Line.new([
            CryTUI::Span.new(heading, CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new(badge, CryTUI::Style.new(foreground: theme.badge_foreground, background: theme.badge_background, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new(hint, CryTUI::Style.new(foreground: theme.muted)),
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

        # Split so the spans concatenate back to
        # `SceneProfileListLayout.row_text`, which is what the box was measured
        # and hit-tested against.
        #
        # The marker travels with the name rather than with the label so the
        # two carry one colour between them: "this is the profile in effect" is
        # one fact, not two.
        private def item(entry : TUI::SceneProfileList::Entry, model : Model) : CryTUI::Widgets::ListItem
          theme = model.theme
          label = entry.label
          label_style = label ? CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new(foreground: theme.muted)
          name_style = CryTUI::Style.new(foreground: entry.active ? theme.success : theme.foreground)
          line = CryTUI::Line.new([
            CryTUI::Span.new(" #{label || ' '}", label_style),
            CryTUI::Span.new("  ", CryTUI::Style.new(foreground: theme.muted)),
            CryTUI::Span.new("#{SceneProfileListLayout.marker(model, entry.active)}  #{entry.name}", name_style),
            CryTUI::Span.new("#{SceneProfileListLayout.count_suffix(model, entry)} ", CryTUI::Style.new(foreground: theme.muted)),
          ])
          CryTUI::Widgets::ListItem.new([line], entry.active ? CryTUI::Style.new(modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new)
        end
      end
    end
  end
end
