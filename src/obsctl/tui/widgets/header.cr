require "./chrome"

module Obsctl
  module TUI
    module Widgets
      module Header
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          block = CryTUI::Widgets::Block.new(
            title: "OBSCTL // BROADCAST COMMAND CENTER",
            border_style: CryTUI::Style.new(foreground: theme.border),
            border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII
          )
          daemon = model.connected_to_daemon
          obs = model.obs_connected?
          lines = [
            CryTUI::Line.new([
              CryTUI::Span.new("#{model.symbol("⚡", "#")} obsctl", CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold)),
              CryTUI::Span.new("  studio automation console  |  ", CryTUI::Style.new(foreground: theme.muted)),
              CryTUI::Span.new("frame #{model.anim.frame.to_s.rjust(6, '0')}", CryTUI::Style.new(foreground: theme.info)),
            ]),
            status_line(model, daemon, obs),
          ]
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end

        private def status_line(model : Model, daemon : Bool, obs : Bool) : CryTUI::Line
          theme = model.theme
          spans = [
            CryTUI::Span.new("#{Chrome.status_dot(daemon, model.rich_ui?)} daemon #{daemon ? "connected" : "disconnected"}", status_style(daemon, theme.success, theme.danger)),
            CryTUI::Span.new("  "),
            CryTUI::Span.new("#{Chrome.status_dot(obs, model.rich_ui?)} OBS: #{obs ? model.snapshot.try(&.obs_studio_version) || "connected" : "disconnected"}", status_style(obs, theme.success, theme.warning)),
          ]
          if scene = model.current_scene
            spans << CryTUI::Span.new(model.advanced_ui ? "  ◆ " : "  > ", CryTUI::Style.new(foreground: theme.accent_alt))
            spans << CryTUI::Span.new("scene: #{scene}", CryTUI::Style.new(foreground: theme.foreground))
          end
          if profile = model.current_profile
            spans << CryTUI::Span.new(model.advanced_ui ? "  ◇ " : "  - ", CryTUI::Style.new(foreground: theme.info))
            spans << CryTUI::Span.new("profile: #{profile}", CryTUI::Style.new(foreground: theme.muted))
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
