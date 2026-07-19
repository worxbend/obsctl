require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module SceneMap
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          grouped = Hash(String, Array(OBS::State::SceneState)).new { |hash, key| hash[key] = [] of OBS::State::SceneState }
          ungrouped = [] of OBS::State::SceneState
          model.scenes.each do |scene|
            if group = scene.group
              grouped[group] << scene
            else
              ungrouped << scene
            end
          end
          items = [] of CryTUI::Widgets::ListItem
          grouped.keys.sort!.each do |group|
            items << item("[#{group}]", theme.accent, bold: true)
            grouped[group].each { |scene| items << scene_item(scene, model) }
          end
          unless ungrouped.empty?
            items << item("[ungrouped]", theme.muted) unless grouped.empty?
            ungrouped.each { |scene| items << scene_item(scene, model) }
          end
          block = CryTUI::Widgets::Block.new(title: " Scene Map ", border_style: CryTUI::Style.new(foreground: theme.border), border_set: CryTUI::Widgets::BorderSet::ASCII)
          CryTUI::Widgets::List.new(items, block: block).render(area, buffer, CryTUI::Widgets::ListState.new)
        end

        private def scene_item(scene : OBS::State::SceneState, model : Model)
          marker = scene.active ? model.symbol("▶ ", "> ") : "  "
          color = scene.active ? model.theme.success : model.theme.muted
          line = CryTUI::Line.new([CryTUI::Span.new(marker, CryTUI::Style.new(foreground: color)), CryTUI::Span.new(scene.name, CryTUI::Style.new(foreground: model.theme.foreground))])
          CryTUI::Widgets::ListItem.new([line])
        end

        private def item(text : String, color : CryTUI::Color, bold = false)
          modifiers = bold ? CryTUI::Modifier::Bold : CryTUI::Modifier::None
          CryTUI::Widgets::ListItem.from(text, CryTUI::Style.new(foreground: color, modifiers: modifiers))
        end
      end
    end
  end
end
