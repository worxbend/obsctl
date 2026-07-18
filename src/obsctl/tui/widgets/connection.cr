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
                    [CryTUI::Line.from("Not connected to obsctl server", CryTUI::Style.new(foreground: theme.danger)), CryTUI::Line.from("Press R to retry")]
                  elsif snapshot = model.snapshot
                    result = [CryTUI::Line.from(snapshot.connected ? "OBS connected" : "OBS disconnected")]
                    result << CryTUI::Line.from("last error: #{snapshot.last_error}", CryTUI::Style.new(foreground: theme.warning)) if snapshot.last_error
                    result
                  else
                    [CryTUI::Line.from("Waiting for server state...")]
                  end
          block = CryTUI::Widgets::Block.new(title: "Connection", border_style: CryTUI::Style.new(foreground: theme.border), border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII)
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end

        def render_unavailable(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          error = model.last_result || "Could not connect to the local obsctl server"
          lines = [
            CryTUI::Line.from("#{model.symbol("⚠", "!")}  obsctl server is not running", CryTUI::Style.new(foreground: theme.danger, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Line.from(""),
            CryTUI::Line.from(error, CryTUI::Style.new(foreground: theme.warning)),
            CryTUI::Line.from(""),
            CryTUI::Line.from("Start the daemon with:"),
            CryTUI::Line.from("  obsctl server --headless", CryTUI::Style.new(foreground: theme.info)),
            CryTUI::Line.from("Or install the user service:"),
            CryTUI::Line.from("  obsctl service install", CryTUI::Style.new(foreground: theme.info)),
            CryTUI::Line.from("  systemctl --user enable --now obsctl.service", CryTUI::Style.new(foreground: theme.info)),
            CryTUI::Line.from(""),
            CryTUI::Line.from("Press R to retry or q to quit", CryTUI::Style.new(foreground: theme.muted)),
          ]
          title = model.advanced_ui ? Anim.gradient_line("SERVER UNAVAILABLE", theme.danger, theme.warning, model.anim.frame, true) : CryTUI::Line.from("SERVER UNAVAILABLE", CryTUI::Style.new(foreground: theme.danger, modifiers: CryTUI::Modifier::Bold))
          border = model.advanced_ui ? Anim.blend(theme.danger, theme.warning, model.anim.pulse(24_u64)) : theme.danger
          block = CryTUI::Widgets::Block.new(title: title, border_style: CryTUI::Style.new(foreground: border), border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::DOUBLE : CryTUI::Widgets::BorderSet::ASCII)
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end
      end
    end
  end
end
