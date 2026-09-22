require "./chrome"
require "../anim"
require "../layout"

module Obsctl
  module TUI
    module Widgets
      module Settings
        extend self

        @@theme_list_items = {} of Bool => Array(CryTUI::Widgets::ListItem)
        @@ascii_preview_lines = {} of String => Array(CryTUI::Line)
        @@rich_preview_tail = {} of String => Array(CryTUI::Line)

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          buffer.set_style(area, CryTUI::Style.new(background: theme.background, foreground: theme.foreground))
          title = if model.advanced_ui
                    Anim.gradient_line(" ⚙ Settings // Appearance Lab // ↑↓ preview · Enter apply · Esc cancel ", theme.accent, theme.accent_alt, model.anim.frame, true)
                  else
                    CryTUI::Line.from(" Settings // Appearance // arrows preview | Enter apply | Esc cancel ", CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold))
                  end
          outer = CryTUI::Widgets::Block.new(
            title: title,
            border_style: CryTUI::Style.new(foreground: theme.border_focus),
            border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::DOUBLE : CryTUI::Widgets::BorderSet::ASCII
          )
          outer.render(area, buffer)
          # Through the shared layout so a click resolves against the same
          # columns the themes were drawn in.
          sections = SettingsLayout.compute(area)
          render_theme_list(sections.themes, buffer, model)
          render_preview(sections.preview, buffer, model)
        end

        private def render_theme_list(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          block = CryTUI::Widgets::Block.new(
            title: " Themes // #{Theme::ALL.size.to_s.rjust(2, '0')} palettes ",
            border_style: CryTUI::Style.new(foreground: theme.border),
            border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII
          )
          state = CryTUI::Widgets::ListState.new(selected: model.settings.settings_cursor)
          highlight = CryTUI::Style.new(foreground: theme.highlight_foreground, background: theme.highlight_background, modifiers: CryTUI::Modifier::Bold)
          CryTUI::Widgets::List.new(theme_list_items(model.advanced_ui), highlight_style: highlight, block: block).render(area, buffer, state)
        end

        private def render_preview(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          block = CryTUI::Widgets::Block.new(
            title: " Preview: #{theme.label} ",
            border_style: CryTUI::Style.new(foreground: theme.border_focus),
            border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII
          )
          lines = model.advanced_ui ? rich_preview(model) : ascii_preview(model)
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end

        private def rich_preview(model : Model) : Array(CryTUI::Line)
          theme = model.theme
          lines = [Anim.gradient_line("◈ OBSCTL // THEME PREVIEW", theme.accent, theme.accent_alt, model.anim.frame, true)]
          lines.concat(rich_preview_tail(theme))
          lines
        end

        private def ascii_preview(model : Model) : Array(CryTUI::Line)
          @@ascii_preview_lines[model.theme.id] ||= build_ascii_preview(model.theme)
        end

        # These rows are static for a given palette, so caching them keeps the
        # settings overlay from rebuilding the same 41 swatches every frame.
        private def theme_list_items(advanced_ui : Bool) : Array(CryTUI::Widgets::ListItem)
          @@theme_list_items[advanced_ui] ||= build_theme_list_items(advanced_ui)
        end

        private def build_theme_list_items(advanced_ui : Bool) : Array(CryTUI::Widgets::ListItem)
          cell = advanced_ui ? "██" : "##"
          Theme::ALL.map do |candidate|
            line = CryTUI::Line.new([
              CryTUI::Span.new(cell, CryTUI::Style.new(foreground: candidate.accent)),
              CryTUI::Span.new(cell, CryTUI::Style.new(foreground: candidate.success)),
              CryTUI::Span.new(cell, CryTUI::Style.new(foreground: candidate.warning)),
              CryTUI::Span.new(cell, CryTUI::Style.new(foreground: candidate.danger)),
              CryTUI::Span.new("  #{candidate.label}"),
            ])
            CryTUI::Widgets::ListItem.new([line])
          end
        end

        private def rich_preview_tail(theme : Theme) : Array(CryTUI::Line)
          @@rich_preview_tail[theme.id] ||= build_rich_preview_tail(theme)
        end

        private def build_rich_preview_tail(theme : Theme) : Array(CryTUI::Line)
          [
            line(""),
            spans([{"● LIVE", theme.danger}, {"   ◉ REC", theme.warning}, {"   ◆ SCENE ACTIVE", theme.accent}]),
            colored("✓ connected", theme.success), colored("⚠ warning", theme.warning), colored("ℹ info", theme.info),
            spans([{"▰▰▰▰", theme.success}, {"▰▰▰", theme.warning}, {"▰▰", theme.danger}, {"▱▱▱  -12.4 dB", theme.muted}]),
            colored("CPU  ▁▂▃▅▄▆▇█▆▄   NET  ▁▁▂▃▅▇▅▃", theme.info), colored("muted text", theme.muted), line(""),
            CryTUI::Line.from(" selected row ", CryTUI::Style.new(foreground: theme.highlight_foreground, background: theme.highlight_background)),
          ]
        end

        private def build_ascii_preview(theme : Theme) : Array(CryTUI::Line)
          [colored("OBSCTL // THEME PREVIEW", theme.accent), line(""),
           spans([{"* LIVE", theme.danger}, {"   * REC", theme.warning}, {"   > SCENE ACTIVE", theme.accent}]),
           colored("+ connected", theme.success), colored("! warning", theme.warning), colored("i info", theme.info),
           colored("#######...  -12.4 dB", theme.success), colored("CPU  .-=+*#*+   NET  ..-=*#+-", theme.info),
           colored("muted text", theme.muted), line(""),
           CryTUI::Line.from(" selected row ", CryTUI::Style.new(foreground: theme.highlight_foreground, background: theme.highlight_background))]
        end

        private def spans(values : Array(Tuple(String, CryTUI::Color))) : CryTUI::Line
          CryTUI::Line.new(values.map { |text, color| CryTUI::Span.new(text, CryTUI::Style.new(foreground: color)) })
        end

        private def colored(text : String, color : CryTUI::Color) : CryTUI::Line
          CryTUI::Line.from(text, CryTUI::Style.new(foreground: color))
        end

        private def line(text : String) : CryTUI::Line
          CryTUI::Line.from(text)
        end
      end
    end
  end
end
