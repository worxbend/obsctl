require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module ResourceList
        extend self

        def render(area, buffer, model, names, current, cursor, focused, icon, label, hint)
          theme = model.theme
          items = names.map_with_index do |name, index|
            active = name == current
            marker = active ? model.symbol("▶", ">") : model.symbol("◇", " ")
            line = CryTUI::Line.new([
              CryTUI::Span.new(" #{(index + 1).to_s.rjust(2, '0')} ", CryTUI::Style.new(foreground: theme.muted)),
              CryTUI::Span.new("#{marker} ", CryTUI::Style.new(foreground: active ? theme.success : theme.muted)),
              CryTUI::Span.new(name, CryTUI::Style.new(foreground: theme.foreground)),
            ])
            CryTUI::Widgets::ListItem.new([line], active ? CryTUI::Style.new(modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new)
          end
          block = Chrome.panel(icon, label, hint, items.size, focused, model)
          highlight = focused ? CryTUI::Style.new(foreground: theme.highlight_foreground, background: theme.highlight_background, modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new(modifiers: CryTUI::Modifier::Dim)
          state = CryTUI::Widgets::ListState.new(selected: items.empty? ? nil : cursor)
          CryTUI::Widgets::List.new(items, highlight_style: highlight, block: block).render(area, buffer, state)
        end
      end
    end
  end
end
