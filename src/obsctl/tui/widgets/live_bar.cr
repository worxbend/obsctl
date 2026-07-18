require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module LiveBar
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          block = CryTUI::Widgets::Block.new(title: "#{model.symbol("◉", "*")} LIVE TELEMETRY", border_style: CryTUI::Style.new(foreground: model.streaming? || model.recording? ? theme.danger : theme.border), border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII)
          first = CryTUI::Line.new([
            badge("LIVE", model.streaming?, model), CryTUI::Span.new("  "),
            badge("REC", model.recording?, model), separator(model),
            CryTUI::Span.new("#{model.symbol("🎬", "SCN")} #{model.current_scene || "no active scene"}", CryTUI::Style.new(foreground: theme.foreground)),
          ])
          second = CryTUI::Line.new([
            CryTUI::Span.new("#{model.symbol("⌁", "~")} telemetry", CryTUI::Style.new(foreground: theme.info)),
            CryTUI::Span.new(model.advanced_ui ? "  waiting for OBS metrics…" : "  waiting for OBS metrics...", CryTUI::Style.new(foreground: theme.muted)),
          ])
          CryTUI::Widgets::StyledText.new([first, second], block: block).render(area, buffer)
        end

        private def badge(label : String, active : Bool, model : Model) : CryTUI::Span
          if active
            CryTUI::Span.new(" #{model.symbol("●", "*")} #{label} --:-- ", CryTUI::Style.new(foreground: model.theme.danger, modifiers: CryTUI::Modifier::Bold | CryTUI::Modifier::Reversed))
          else
            CryTUI::Span.new(" #{model.symbol("○", "-")} #{label} off ", CryTUI::Style.new(foreground: model.theme.muted))
          end
        end

        private def separator(model : Model) : CryTUI::Span
          CryTUI::Span.new(model.advanced_ui ? "  │  " : "  |  ", CryTUI::Style.new(foreground: model.theme.border))
        end
      end
    end
  end
end
