require "./chrome"
require "./status_beacon"
require "../anim"

module Obsctl
  module TUI
    module Widgets
      module Header
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          pulse = model.anim.pulse(30_u64)
          title = model.advanced_ui ? Anim.gradient_line(" ◈ OBSCTL // BROADCAST COMMAND CENTER ", theme.accent, theme.accent_alt, model.anim.frame, true) : CryTUI::Line.from(" OBSCTL // BROADCAST COMMAND CENTER ", CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold))
          block = CryTUI::Widgets::Block.new(
            title: title,
            border_style: CryTUI::Style.new(foreground: model.advanced_ui ? Anim.blend(theme.border, theme.accent, pulse * 0.45) : theme.border),
            border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII
          )
          daemon = model.connected_to_daemon
          obs = model.obs_connected?
          identity = [
            CryTUI::Span.new("#{model.symbol("⚡", "#")} obsctl", CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new("  studio automation console", CryTUI::Style.new(foreground: theme.muted)),
            CryTUI::Span.new(model.advanced_ui ? "  •  " : "  |  ", CryTUI::Style.new(foreground: theme.border)),
            CryTUI::Span.new("frame #{model.anim.frame.to_s.rjust(6, '0')}", CryTUI::Style.new(foreground: theme.info)),
          ]
          lines = [
            CryTUI::Line.new(identity + pulse_spans(model, daemon)),
            status_line(model, daemon, obs),
          ]
          # The beacon is given a column of the header rather than drawn over
          # it, so a long scene or profile name can never run underneath the
          # one indicator that has to stay legible.
          block.render(area, buffer)
          text_area, beacon_area = StatusBeacon.reserve(block.inner(area), model)
          CryTUI::Widgets::StyledText.new(lines).render(text_area, buffer)
          beacon_area.try { |rect| StatusBeacon.render(rect, buffer, model) }
        end

        # A wave that only moves while the daemon is answering, so a frozen
        # header is visible as a frozen header rather than as a stale number.
        private def pulse_spans(model : Model, daemon : Bool) : Array(CryTUI::Span)
          return [] of CryTUI::Span unless model.advanced_ui
          theme = model.theme
          spinner = CryTUI::Widgets::FluxSpinner.new(
            daemon ? model.anim.frame : 0_u64,
            width: 6,
            frames: CryTUI::Widgets::FluxFrames::ORBIT,
            color: daemon ? theme.accent_alt : theme.muted,
            ticks_per_step: 2_u64
          )
          [CryTUI::Span.new("  •  ", CryTUI::Style.new(foreground: theme.border))] + Anim.spans(spinner.lines)
        end

        private def status_line(model : Model, daemon : Bool, obs : Bool) : CryTUI::Line
          theme = model.theme
          spans = [
            CryTUI::Span.new("#{Chrome.status_dot(daemon, model.rich_ui?)} #{Localization.text(model.locale, daemon ? :daemon_connected : :daemon_disconnected)}", status_style(daemon, theme.success, theme.danger)),
            CryTUI::Span.new("  "),
            CryTUI::Span.new("#{Chrome.status_dot(obs, model.rich_ui?)} #{obs ? Localization.text(model.locale, :obs_connected, model.snapshot.try(&.obs_studio_version)) : Localization.text(model.locale, :obs_disconnected)}", status_style(obs, theme.success, theme.warning)),
          ]
          if scene = model.current_scene
            spans << CryTUI::Span.new(model.advanced_ui ? "  ◆ " : "  > ", CryTUI::Style.new(foreground: theme.accent_alt))
            spans << CryTUI::Span.new(Localization.text(model.locale, :scene, scene), CryTUI::Style.new(foreground: theme.foreground))
          end
          if profile = model.current_profile
            spans << CryTUI::Span.new(model.advanced_ui ? "  ◇ " : "  - ", CryTUI::Style.new(foreground: theme.info))
            spans << CryTUI::Span.new(Localization.text(model.locale, :profile, profile), CryTUI::Style.new(foreground: theme.muted))
          end
          CryTUI::Line.new(spans)
        end

        private def status_style(active : Bool, active_color : CryTUI::Color, inactive_color : CryTUI::Color)
          CryTUI::Style.new(foreground: active ? active_color : inactive_color, modifiers: CryTUI::Modifier::Bold)
        end
      end
    end
  end
end
