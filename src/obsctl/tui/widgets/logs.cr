require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module Logs
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          visible = {area.height - 2, 0}.max
          entries = model.logs.last(visible)
          items = entries.map do |entry|
            color, marker = level_appearance(entry.level, model)
            line = CryTUI::Line.new([
              CryTUI::Span.new(" #{marker} ", CryTUI::Style.new(foreground: color)),
              CryTUI::Span.new(entry.timestamp.to_s("%H:%M:%S"), CryTUI::Style.new(foreground: model.theme.muted)),
              CryTUI::Span.new(" #{entry.level.to_s.upcase.ljust(5)} ", CryTUI::Style.new(foreground: color, modifiers: CryTUI::Modifier::Bold)),
              CryTUI::Span.new(entry.code ? "#{entry.code}  " : "", CryTUI::Style.new(foreground: model.theme.accent_alt)),
              CryTUI::Span.new(entry.message, CryTUI::Style.new(foreground: model.theme.foreground)),
            ])
            CryTUI::Widgets::ListItem.new([line])
          end
          block = Chrome.panel(model.symbol("📡", "L"), "Logs // Event Stream", "live daemon feed", model.logs.size, false, model)
          CryTUI::Widgets::List.new(items, block: block).render(area, buffer, CryTUI::Widgets::ListState.new)
        end

        private def level_appearance(level : Runtime::LogLevel, model : Model) : Tuple(CryTUI::Color, String)
          case level
          when .info?  then {model.theme.info, model.symbol("●", "i")}
          when .warn?  then {model.theme.warning, model.symbol("▲", "!")}
          when .error? then {model.theme.danger, model.symbol("◆", "x")}
          else              {model.theme.muted, model.symbol("◦", ".")}
          end
        end
      end
    end
  end
end
