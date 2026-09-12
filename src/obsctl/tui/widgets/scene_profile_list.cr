require "../layout"
require "../overlay_layout"
require "../scene_profile_list"
require "./overlay"

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
          frame = block(model, entries.size)
          items = entries.map { |entry| item(entry, model) }
          # The block is drawn here rather than handed to the list, because the
          # list gets only the rows above the hint row and the border is around
          # both of them.
          Overlay.render_framed_list(
            rect,
            frame.inner(SceneProfileListLayout.list_area(rect)),
            buffer,
            frame,
            items,
            model.scene_profile_list.cursor,
            theme
          )
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
          theme = model.theme
          colour = model.scene_profile_list.confirming ? theme.warning : theme.muted
          Overlay.hint_line(buffer, inner, SceneProfileListLayout.hint_row(rect), SceneProfileListLayout.hint_text(model, rect.width), colour, model)
        end

        private def block(model : Model, count : Int32) : CryTUI::Widgets::Block
          # Through the shared layout, so the title drawn is the title the box
          # was sized around.
          heading, badge, hint = SceneProfileListLayout.title_parts(model, count)
          Overlay.block(model, Overlay.title(model, heading, badge, hint))
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
