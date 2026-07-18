require "../../../crytui"
require "../model"
require "../anim"

module Obsctl
  module TUI
    module Widgets
      module Chrome
        extend self

        def panel(icon : String, label : String, hint : String, count : Int32, focused : Bool, model : Model) : CryTUI::Widgets::Block
          heading = " #{icon}  #{label} "
          spans = if model.advanced_ui
                    Anim.gradient_line(heading, model.theme.accent, model.theme.accent_alt, model.anim.frame, true).spans
                  else
                    [CryTUI::Span.new(heading, CryTUI::Style.new(foreground: model.theme.accent, modifiers: CryTUI::Modifier::Bold))]
                  end
          spans << CryTUI::Span.new(" #{count.to_s.rjust(2, '0')} ", CryTUI::Style.new(foreground: model.theme.highlight_foreground, background: model.theme.highlight_background, modifiers: CryTUI::Modifier::Bold))
          spans << CryTUI::Span.new("  #{hint} ", CryTUI::Style.new(foreground: model.theme.muted)) unless hint.empty?
          CryTUI::Widgets::Block.new(
            title: CryTUI::Line.new(spans),
            border_style: CryTUI::Style.new(foreground: focused && model.advanced_ui ? Anim.blend(model.theme.border_focus, model.theme.accent_alt, 0.25) : (focused ? model.theme.border_focus : model.theme.border)),
            border_set: model.advanced_ui ? (focused ? CryTUI::Widgets::BorderSet::THICK : CryTUI::Widgets::BorderSet::ROUNDED) : CryTUI::Widgets::BorderSet::ASCII
          )
        end

        def status_dot(active : Bool, fancy : Bool) : String
          active ? (fancy ? "●" : "*") : (fancy ? "○" : "-")
        end
      end
    end
  end
end
