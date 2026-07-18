require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module Scenes
        extend self

        FLASH_DURATION = 8_u64

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          focused = model.focus.scenes?
          items = model.scenes.map_with_index do |scene, index|
            flashing = flash?(model, scene.name)
            marker = scene.active ? model.symbol("▶", ">") : model.symbol("◇", " ")
            spans = [
              CryTUI::Span.new(" #{(index + 1).to_s.rjust(2, '0')} ", CryTUI::Style.new(foreground: theme.muted)),
              CryTUI::Span.new("#{marker} ", CryTUI::Style.new(foreground: scene.active ? theme.success : theme.muted)),
              CryTUI::Span.new(scene.name, CryTUI::Style.new(foreground: flashing ? theme.accent : theme.foreground)),
            ]
            spans << CryTUI::Span.new(" (#{scene.alias})", CryTUI::Style.new(foreground: theme.muted)) if scene.alias
            spans << CryTUI::Span.new(" [#{scene.shortcut}]", CryTUI::Style.new(foreground: theme.warning)) if scene.shortcut
            spans << CryTUI::Span.new("  #{model.advanced_ui ? "⟨#{scene.group}⟩" : "[#{scene.group}]"}", CryTUI::Style.new(foreground: theme.accent_alt)) if scene.group
            style = scene.active ? CryTUI::Style.new(modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new
            CryTUI::Widgets::ListItem.new([CryTUI::Line.new(spans)], style)
          end
          block = Chrome.panel(model.symbol("🎬", "S"), "Scenes", model.symbol("[s]  ↵ switch", "[s] Enter switch"), items.size, focused, model)
          highlight = focused ? CryTUI::Style.new(foreground: theme.highlight_foreground, background: theme.highlight_background, modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new(modifiers: CryTUI::Modifier::Dim)
          state = CryTUI::Widgets::ListState.new(selected: items.empty? ? nil : model.scene_cursor)
          CryTUI::Widgets::List.new(items, highlight_style: highlight, block: block).render(area, buffer, state)
        end

        private def flash?(model : Model, name : String) : Bool
          flash = model.scene_flash
          return false unless flash && flash[0] == name
          model.anim.frame >= flash[1] && model.anim.frame - flash[1] < FLASH_DURATION
        end
      end
    end
  end
end
