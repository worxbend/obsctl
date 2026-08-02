require "../layout"
require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module CommandPalette
        extend self

        REVEAL_PER_FRAME = 3

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          palette = model.command_palette
          hint = palette.active ? model.symbol("type command  ↵ run  esc close", "type command Enter run Esc close") : ": open  space keys  q quit"
          block = Chrome.panel(model.symbol("⌘", ">"), "Command Palette", hint, palette.completions.size, palette.active, model)
          lines = [result_line(model), prompt_line(model)]
          lines << completion_line(model) if palette.active
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end

        private def result_line(model : Model) : CryTUI::Line
          full = model.last_result
          return CryTUI::Line.from("") unless full
          revealed = model.revealed_last_result(REVEAL_PER_FRAME) || ""
          color = full.starts_with?("error") ? model.theme.danger : model.theme.success
          spans = [CryTUI::Span.new("#{model.symbol("✉", "msg:")}  #{revealed}", CryTUI::Style.new(foreground: color))]
          spans << CryTUI::Span.new(model.advanced_ui ? "▌" : "_", CryTUI::Style.new(foreground: model.theme.accent)) if revealed.grapheme_size < full.grapheme_size
          CryTUI::Line.new(spans)
        end

        private def prompt_line(model : Model) : CryTUI::Line
          palette = model.command_palette
          unless palette.active
            text = model.advanced_ui ? "  ◈  : command  │  ␣ leader  │  gg/G  │  F2 themes  │  q quit" : "  >  : command  |  space leader  |  gg/G  |  F2 themes  |  q quit"
            return CryTUI::Line.from(text, CryTUI::Style.new(foreground: model.theme.muted))
          end
          CryTUI::Line.new([
            CryTUI::Span.new("#{model.symbol("❯", ">")}  ", CryTUI::Style.new(foreground: model.theme.accent, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new(palette.input),
            CryTUI::Span.new(model.advanced_ui ? "█" : "_", CryTUI::Style.new(foreground: model.theme.accent)),
          ])
        end

        private def completion_line(model : Model) : CryTUI::Line
          palette = model.command_palette
          if palette.completions.empty?
            return CryTUI::Line.from("  no completions", CryTUI::Style.new(foreground: model.theme.muted, modifiers: CryTUI::Modifier::Dim))
          end
          # Indent, chip text, and gap come from `PaletteLayout` so a click can
          # be resolved back to the chip that was drawn.
          spans = [CryTUI::Span.new(" " * PaletteLayout::INDENT)]
          PaletteLayout.visible(palette.completions).each_with_index do |completion, index|
            spans << CryTUI::Span.new(" " * PaletteLayout::GAP) if index > 0
            style = index == palette.completion_index ? CryTUI::Style.new(foreground: model.theme.accent, modifiers: CryTUI::Modifier::Bold) : CryTUI::Style.new(foreground: model.theme.muted)
            spans << CryTUI::Span.new(PaletteLayout.label(completion), style)
          end
          CryTUI::Line.new(spans)
        end
      end
    end
  end
end
