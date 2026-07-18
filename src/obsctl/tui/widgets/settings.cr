require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module Settings
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          buffer.set_style(area, CryTUI::Style.new(background: model.theme.background, foreground: model.theme.foreground))
          block = CryTUI::Widgets::Block.new(title: "THEME SETTINGS", border_style: CryTUI::Style.new(foreground: model.theme.border_focus), border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::DOUBLE : CryTUI::Widgets::BorderSet::ASCII)
          items = Theme::ALL.map do |theme|
            active = theme == model.theme
            marker = active ? model.symbol("▶", ">") : " "
            CryTUI::Widgets::ListItem.from(" #{marker} #{theme.label}  [#{theme.id}]", active ? CryTUI::Style.new(modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new)
          end
          state = CryTUI::Widgets::ListState.new(selected: model.settings_cursor)
          highlight = CryTUI::Style.new(foreground: model.theme.highlight_foreground, background: model.theme.highlight_background, modifiers: CryTUI::Modifier::Bold)
          CryTUI::Widgets::List.new(items, highlight_style: highlight, block: block).render(area, buffer, state)
          hint = "↑/↓ or j/k preview  Enter apply  Esc cancel"
          CryTUI::Line.from(hint, CryTUI::Style.new(foreground: model.theme.muted), CryTUI::Alignment::Center).render(buffer, CryTUI::Rect.new(area.x + 1, area.bottom - 2, {area.width - 2, 0}.max, 1))
        end
      end
    end
  end
end
