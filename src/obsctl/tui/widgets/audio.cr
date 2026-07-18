require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module Audio
        extend self

        METER_WIDTH =    20
        FLOOR_DB    = -60.0

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          focused = model.focus.audio?
          items = model.audio_inputs.map do |input|
            mute_span = case input.muted
                        when true  then CryTUI::Span.new("#{model.symbol("🔇", "M")} ", CryTUI::Style.new(foreground: theme.danger))
                        when false then CryTUI::Span.new("#{model.symbol("🔊", "A")} ", CryTUI::Style.new(foreground: theme.success))
                        else            CryTUI::Span.new("   ")
                        end
            spans = [
              mute_span,
              CryTUI::Span.new(input.name, CryTUI::Style.new(foreground: theme.foreground)),
            ]
            spans << CryTUI::Span.new(" (#{input.alias})", CryTUI::Style.new(foreground: theme.muted)) if input.alias
            spans << CryTUI::Span.new(" [#{input.shortcut}]", CryTUI::Style.new(foreground: theme.warning)) if input.shortcut
            spans << CryTUI::Span.new(" #{input.volume_percent}%", CryTUI::Style.new(foreground: theme.info)) if input.volume_percent
            lines = [CryTUI::Line.new(spans)]
            if level = model.meter_levels[input.name]?
              lines << meter_line(level, input.muted == true, model)
            end
            CryTUI::Widgets::ListItem.new(lines)
          end
          block = Chrome.panel(model.symbol("🎚", "A"), "Audio Matrix", model.symbol("[a]  m mute  ←/→ gain", "[a]  m mute  </> gain"), items.size, focused, model)
          highlight = focused ? CryTUI::Style.new(foreground: theme.highlight_foreground, background: theme.highlight_background, modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new(modifiers: CryTUI::Modifier::Dim)
          state = CryTUI::Widgets::ListState.new(selected: items.empty? ? nil : model.audio_cursor)
          CryTUI::Widgets::List.new(items, highlight_style: highlight, block: block).render(area, buffer, state)
        end

        private def meter_line(level : Float64, muted : Bool, model : Model) : CryTUI::Line
          theme = model.theme
          db = level < 1e-7 ? FLOOR_DB : {20.0 * Math.log10(level), FLOOR_DB}.max
          filled = (((db - FLOOR_DB) / -FLOOR_DB).clamp(0.0, 1.0) * METER_WIDTH).to_i
          spans = [CryTUI::Span.new(model.advanced_ui ? "  ╰─ " : "  +- ", CryTUI::Style.new(foreground: theme.border))]
          METER_WIDTH.times do |index|
            color = if muted
                      theme.muted
                    elsif index > METER_WIDTH * 0.85
                      theme.danger
                    elsif index > METER_WIDTH * 0.65
                      theme.warning
                    else
                      Anim.blend(theme.success, theme.info, index / (METER_WIDTH * 0.65))
                    end
            symbol = index < filled ? model.symbol("▰", "#") : model.symbol("▱", ".")
            spans << CryTUI::Span.new(symbol, CryTUI::Style.new(foreground: index < filled ? color : theme.border))
          end
          spans << CryTUI::Span.new("  #{sprintf("%5.1f", db)} dB", CryTUI::Style.new(foreground: muted ? theme.muted : theme.info))
          CryTUI::Line.new(spans)
        end
      end
    end
  end
end
