require "crytui"
require "../model"

module Obsctl
  module TUI
    module Widgets
      # The chrome every floating overlay shares -- the scene picker, the
      # scene-profile list, the scene-profile editor and the which-key menu.
      #
      # Kept apart from `Chrome`, which dresses the dashboard's own panels,
      # because the two want opposite treatment of the cells underneath: a
      # panel is transparent, an overlay is a box laid on top of a dashboard
      # that has already been painted.
      module Overlay
        extend self

        # Blanks the cells the box is about to cover. Overlays are drawn after
        # the dashboard, so without this the panels underneath show through
        # everywhere the box does not paint a character of its own.
        def clear(rect : CryTUI::Rect, buffer : CryTUI::Buffer, theme : Theme)
          style = CryTUI::Style.new(background: theme.background, foreground: theme.foreground)
          blank = " " * rect.width
          (rect.y...rect.bottom).each { |row| buffer.set_string(rect.x, row, blank, style) }
        end

        # The bar drawn over the row the cursor is on.
        def highlight_style(theme : Theme) : CryTUI::Style
          CryTUI::Style.new(
            foreground: theme.highlight_foreground,
            background: theme.highlight_background,
            modifiers: CryTUI::Modifier::Bold
          )
        end

        # The accent heading, count/name badge, and muted hint are reused
        # across overlays so they stay visually identical to the title widths
        # their matching layout code measured.
        def title(model : Model, heading : String, badge : String? = nil, hint : String? = nil) : CryTUI::Line
          theme = model.theme
          spans = [CryTUI::Span.new(heading, CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold))]
          if badge
            spans << CryTUI::Span.new(
              badge,
              CryTUI::Style.new(
                foreground: theme.badge_foreground,
                background: theme.badge_background,
                modifiers: CryTUI::Modifier::Bold
              )
            )
          end
          spans << CryTUI::Span.new(hint, CryTUI::Style.new(foreground: theme.muted)) if hint && !hint.empty?
          CryTUI::Line.new(spans)
        end

        # The bordered box, built here rather than through `Chrome.panel`
        # because a dashboard panel is transparent and an overlay must not be:
        # the box needs an opaque `style` so the dashboard does not show
        # through its padding.
        #
        # The title is assembled by the caller, because how it splits into
        # styled spans differs per overlay and each split has to concatenate
        # back to the string that overlay's layout measured.
        def block(model : Model, title : CryTUI::Line) : CryTUI::Widgets::Block
          theme = model.theme
          CryTUI::Widgets::Block.new(
            title: title,
            style: CryTUI::Style.new(background: theme.background, foreground: theme.foreground),
            border_style: CryTUI::Style.new(foreground: theme.border_focus),
            border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII
          )
        end

        # Overlay lists share the same layering rules: blank the dashboard
        # beneath them, draw their own border first, then paint the selectable
        # rows only inside the content area that leaves the hint row untouched.
        def render_framed_list(
          rect : CryTUI::Rect,
          content : CryTUI::Rect,
          buffer : CryTUI::Buffer,
          frame : CryTUI::Widgets::Block,
          items : Array(CryTUI::Widgets::ListItem),
          selected : Int32,
          theme : Theme,
        )
          clear(rect, buffer, theme)
          frame.render(rect, buffer)
          state = CryTUI::Widgets::ListState.new(selected: selected)
          CryTUI::Widgets::List.new(items, highlight_style: highlight_style(theme)).render(content, buffer, state)
        end

        # The row of key hints an overlay keeps under its list.
        #
        # Trimmed to the room the box actually has, with an ellipsis, rather
        # than left to run into the border and be cut without a mark. `row` is
        # a screen row from the layout; a box with no inside at all is left
        # alone instead of having its hints painted over the border.
        def hint_line(buffer : CryTUI::Buffer, inner : CryTUI::Rect, row : Int32, text : String, colour : CryTUI::Color, model : Model)
          return if inner.height <= 0

          style = CryTUI::Style.new(foreground: colour, background: model.theme.background)
          buffer.set_string(inner.x, row, CryTUI::TextWidth.truncate(text, inner.width, model.symbol("…", "~")), style, inner.width)
        end
      end
    end
  end
end
