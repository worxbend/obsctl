require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module Scenes
        extend self

        FLASH_DURATION = 8_u64
        # How wide the panel has to be before the active profile's name is worth
        # the columns: below this the title is already competing with the count
        # badge and the key hint, and a block clips its title without saying so.
        PRESET_LABEL_MIN_WIDTH = 40
        # A profile name is whatever the user typed, so it is fitted rather than
        # trusted -- long enough to recognise, short enough to leave the hint on
        # screen.
        PRESET_LABEL_MAX_NAME = 16

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          focused = model.focus.scenes?
          items = model.scenes.map_with_index do |scene, index|
            flash = flash_intensity(model, scene.name)
            active_color = flash > 0 ? Anim.blend(theme.success, theme.accent, flash) : theme.success
            marker = scene.active ? model.symbol("▶", ">") : model.symbol("◇", " ")
            spans = [
              CryTUI::Span.new(" #{(index + 1).to_s.rjust(2, '0')} ", CryTUI::Style.new(foreground: theme.muted)),
              CryTUI::Span.new("#{marker} ", CryTUI::Style.new(foreground: scene.active ? active_color : theme.muted)),
              CryTUI::Span.new(scene.name, CryTUI::Style.new(foreground: flash > 0 ? active_color : theme.foreground)),
            ]
            spans << CryTUI::Span.new(" (#{scene.alias})", CryTUI::Style.new(foreground: theme.muted)) if scene.alias
            spans << CryTUI::Span.new(" [#{scene.shortcut}]", CryTUI::Style.new(foreground: theme.warning)) if scene.shortcut
            spans << CryTUI::Span.new("  #{model.advanced_ui ? "⟨#{scene.group}⟩" : "[#{scene.group}]"}", CryTUI::Style.new(foreground: theme.accent_alt)) if scene.group
            style = scene.active ? CryTUI::Style.new(modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new
            CryTUI::Widgets::ListItem.new([CryTUI::Line.new(spans)], style)
          end
          block = Chrome.panel(model.symbol("🎬", "S"), title_label(model, area), model.symbol("[s]  ↵ switch", "[s]  Enter switch"), items.size, focused, model)
          highlight = focused ? CryTUI::Style.new(foreground: theme.highlight_foreground, background: theme.highlight_background, modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new(modifiers: CryTUI::Modifier::Dim)
          state = CryTUI::Widgets::ListState.new(selected: items.empty? ? nil : model.scene_cursor)
          CryTUI::Widgets::List.new(items, highlight_style: highlight, block: block).render(area, buffer, state)
        end

        # "Scenes", or "Scenes · streaming" when a profile is filtering the list.
        #
        # This is where the name of the active profile belongs, because this is
        # the panel a profile shortens: the count badge beside it already reads a
        # smaller number than OBS reports, and until now nothing on the
        # dashboard said why. With no profile active the title is exactly the
        # word it has always been.
        private def title_label(model : Model, area : CryTUI::Rect) : String
          profile = model.scene_profiles.active_profile
          return "Scenes" unless profile && area.width >= PRESET_LABEL_MIN_WIDTH

          name = CryTUI::TextWidth.truncate(profile.name, PRESET_LABEL_MAX_NAME, model.symbol("…", "~"))
          "Scenes #{model.symbol("·", "-")} #{name}"
        end

        private def flash_intensity(model : Model, name : String) : Float64
          flash = model.scene_flash
          return 0.0 unless flash && flash[0] == name
          return 0.0 if model.anim.frame < flash[1]
          elapsed = model.anim.frame - flash[1]
          return 0.0 if elapsed >= FLASH_DURATION
          1.0 - elapsed.to_f64 / FLASH_DURATION
        end
      end
    end
  end
end
