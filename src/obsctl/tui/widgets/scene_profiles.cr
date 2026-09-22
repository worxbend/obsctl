require "../layout"
require "../overlay_layout"
require "../scene_profiles"
require "./overlay"

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
          frame = block(model, rect)
          items = scenes.map { |scene| item(scene, model) }
          # The block is drawn here rather than handed to the list, because the
          # list gets only the rows above the hint row and the border is around
          # both of them.
          Overlay.render_framed_list(
            rect,
            frame.inner(SceneProfilesLayout.list_area(rect)),
            buffer,
            frame,
            items,
            model.scene_profile_editor.cursor,
            theme
          )
          render_hints(rect, frame.inner(rect), buffer, model)
        end

        # The keys, on the last row inside the border. They are not in the
        # title because the title carries the profile's name, and a name of any
        # length would push them off the end of the line -- taking the way out
        # of the modal with them.
        private def render_hints(rect : CryTUI::Rect, inner : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          Overlay.hint_line(buffer, inner, SceneProfilesLayout.hint_row(rect), SceneProfilesLayout.hint_text(model, rect.width), model.theme.muted, model)
        end

        private def block(model : Model, rect : CryTUI::Rect) : CryTUI::Widgets::Block
          # Through the shared layout, and against the width the box actually
          # got, so the title drawn is the title that fits the box.
          heading, name = SceneProfilesLayout.title_parts(model, rect.width)
          Overlay.block(model, Overlay.title(model, heading, name))
        end

        # Split so the spans concatenate back to `SceneProfilesLayout.row_text`,
        # which is what the box was measured and hit-tested against.
        private def item(scene : State::SceneState, model : Model) : CryTUI::Widgets::ListItem
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
