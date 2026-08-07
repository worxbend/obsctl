require "./chrome"
require "../anim"

module Obsctl
  module TUI
    module Widgets
      module Connection
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          lines = if !model.connected_to_daemon
                    [CryTUI::Line.new(searching_spans(model) + [CryTUI::Span.new(Localization.text(model.locale, :not_connected), CryTUI::Style.new(foreground: theme.danger))]), CryTUI::Line.from(Localization.text(model.locale, :retry))]
                  elsif snapshot = model.snapshot
                    result = [CryTUI::Line.from(Localization.text(model.locale, snapshot.connected ? :obs_state_connected : :obs_state_disconnected))]
                    result << CryTUI::Line.from(Localization.text(model.locale, :last_error, snapshot.last_error), CryTUI::Style.new(foreground: theme.warning)) if snapshot.last_error
                    result
                  else
                    [CryTUI::Line.new(searching_spans(model) + [CryTUI::Span.new(Localization.text(model.locale, :waiting))])]
                  end
          block = CryTUI::Widgets::Block.new(title: Localization.text(model.locale, :connection_title), border_style: CryTUI::Style.new(foreground: theme.border), border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII)
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end

        # A spinner in front of a line that is waiting on something. Callers
        # keep the wording; this only says that obsctl is still trying.
        private def searching_spans(model : Model) : Array(CryTUI::Span)
          return [] of CryTUI::Span unless model.advanced_ui

          spinner = CryTUI::Widgets::FluxSpinner.new(
            model.anim.frame,
            frames: CryTUI::Widgets::FluxFrames::CLASSIC,
            color: model.theme.warning,
            ticks_per_step: 2_u64
          )
          [CryTUI::Span.new("#{spinner.glyph}  ", CryTUI::Style.new(foreground: model.theme.warning))]
        end

        # A ring that keeps turning under the instructions, so a screen full of
        # static text still shows obsctl is running rather than hung.
        private def searching_ring(model : Model) : Array(CryTUI::Line)
          return [] of CryTUI::Line unless model.advanced_ui

          CryTUI::Widgets::CircleSpinner.new(
            model.anim.frame,
            radius: 4,
            arc_color: model.theme.warning,
            dim_color: model.theme.border,
            alignment: CryTUI::Alignment::Center
          ).lines
        end

        def render_unavailable(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          error = model.last_result || Localization.text(model.locale, :could_not_connect)
          lines = [
            CryTUI::Line.from("#{model.symbol("⚠", "!")}  #{Localization.text(model.locale, :daemon_not_running)}", CryTUI::Style.new(foreground: theme.danger, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Line.from(""),
            CryTUI::Line.from(error, CryTUI::Style.new(foreground: theme.warning)),
            CryTUI::Line.from(""),
            CryTUI::Line.from(Localization.text(model.locale, :start_daemon)),
            CryTUI::Line.from("  obsctl server --headless", CryTUI::Style.new(foreground: theme.info)),
            CryTUI::Line.from(Localization.text(model.locale, :install_service)),
            CryTUI::Line.from("  obsctl service install", CryTUI::Style.new(foreground: theme.info)),
            CryTUI::Line.from("  systemctl --user enable --now obsctl.service", CryTUI::Style.new(foreground: theme.info)),
            CryTUI::Line.from(""),
            CryTUI::Line.from(Localization.text(model.locale, :retry), CryTUI::Style.new(foreground: theme.muted)),
          ]
          lines.concat(searching_ring(model)) if area.height >= 16
          localized_title = Localization.text(model.locale, :unavailable_title)
          title = model.advanced_ui ? Anim.gradient_line(localized_title, theme.danger, theme.warning, model.anim.frame, true) : CryTUI::Line.from(localized_title.gsub('—', '-'), CryTUI::Style.new(foreground: theme.danger, modifiers: CryTUI::Modifier::Bold))
          border = model.advanced_ui ? Anim.blend(theme.danger, theme.warning, model.anim.pulse(24_u64)) : theme.danger
          block = CryTUI::Widgets::Block.new(title: title, border_style: CryTUI::Style.new(foreground: border), border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::DOUBLE : CryTUI::Widgets::BorderSet::ASCII)
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end
      end
    end
  end
end
