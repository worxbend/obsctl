require "../anim"

module Obsctl
  module TUI
    module Widgets
      module Splash
        extend self

        TAGLINE    = "Broadcast control, without breaking flow."
        LARGE_LOGO = [
          " ██████╗ ██████╗ ███████╗ ██████╗████████╗██╗     ",
          "██╔═══██╗██╔══██╗██╔════╝██╔════╝╚══██╔══╝██║     ",
          "██║   ██║██████╔╝███████╗██║        ██║   ██║     ",
          "██║   ██║██╔══██╗╚════██║██║        ██║   ██║     ",
          "╚██████╔╝██████╔╝███████║╚██████╗   ██║   ███████╗",
          " ╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝   ╚═╝   ╚══════╝",
        ]
        ASCII_LOGO = [
          "  ___  ____  ____   ____ _____ _     ",
          " / _ \\| __ )/ ___| / ___|_   _| |    ",
          "| | | |  _ \\___ \\| |     | | | |    ",
          "| |_| | |_) |___) | |___  | | | |___ ",
          " \\___/|____/|____/ \\____| |_| |_____|",
        ]

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model, frame : UInt64, total_frames : UInt64)
          theme = model.theme
          buffer.set_style(area, CryTUI::Style.new(background: theme.background, foreground: theme.foreground))
          if !model.advanced_ui
            render_ascii(center(area, {64, area.width}.min, {13, area.height}.min), buffer, model, frame, total_frames)
          elsif area.width >= 76 && area.height >= 16
            render_large(center(area, {88, area.width}.min, {16, area.height}.min), buffer, model, frame, total_frames)
          else
            render_compact(center(area, {56, area.width}.min, {10, area.height}.min), buffer, model, frame, total_frames)
          end
        end

        private def render_compact(area, buffer, model, frame, total)
          theme = model.theme
          orbit = model.show_icons ? ["✦", "✧", "◆", "◇"][(frame // 3 % 4).to_i] : ["*", "+", "o", "."][(frame // 3 % 4).to_i]
          block = CryTUI::Widgets::Block.new(
            title: "#{orbit} INITIALIZING BROADCAST CONTROL #{orbit}",
            border_style: CryTUI::Style.new(foreground: Anim.blend(theme.accent, theme.accent_alt, model.anim.pulse(35_u64))),
            border_set: CryTUI::Widgets::BorderSet::ROUNDED
          )
          lines = [
            line(""),
            Anim.gradient_line("◢ O B S C T L ◣", theme.accent, theme.accent_alt, frame, true, CryTUI::Alignment::Center),
            line(""),
            centered(TAGLINE, theme.foreground),
            live_line(model, frame),
            progress_line(model, frame, total),
            centered(boot_message(frame, total, model.show_icons), theme.muted),
          ]
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end

        private def render_ascii(area, buffer, model, frame, total)
          theme = model.theme
          block = CryTUI::Widgets::Block.new(title: "OBSCTL STARTUP", border_style: CryTUI::Style.new(foreground: theme.accent), border_set: CryTUI::Widgets::BorderSet::ASCII)
          lines = ASCII_LOGO.map { |text| centered(text, theme.accent, true) }
          lines << centered(TAGLINE, theme.foreground)
          lines << centered("Scenes, audio, profiles, recording, and live telemetry.", theme.muted)
          spinner = ["|", "/", "-", "\\"][(frame // 2 % 4).to_i]
          lines << centered("#{spinner}  (o) LIVE  #{spinner}", theme.danger, true)
          lines << line("")
          lines << progress_line(model, frame, total)
          lines << centered("#{spinner} initializing studio link", theme.muted)
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end

        private def render_large(area, buffer, model, frame, total)
          theme = model.theme
          rows = CryTUI::Layout.new(CryTUI::Direction::Vertical, [CryTUI::Constraint.length(6), CryTUI::Constraint.length(3), CryTUI::Constraint.length(7)]).split(area)
          logo = LARGE_LOGO.map_with_index do |text, row|
            Anim.gradient_line(text, theme.accent, theme.accent_alt, frame + row.to_u64 * 2, true, CryTUI::Alignment::Center)
          end
          CryTUI::Widgets::StyledText.new(logo).render(rows[0], buffer)
          identity = [
            Anim.gradient_line(TAGLINE, theme.accent_alt, theme.info, frame, true, CryTUI::Alignment::Center),
            centered("Scenes, audio, profiles, recording, and live telemetry — one command center.", theme.muted),
            live_line(model, frame),
          ]
          CryTUI::Widgets::StyledText.new(identity).render(rows[1], buffer)
          block = CryTUI::Widgets::Block.new(
            title: "STUDIO LINK // SECURE SESSION",
            style: CryTUI::Style.new(background: Anim.blend(theme.background, theme.border, 0.34)),
            border_style: CryTUI::Style.new(foreground: Anim.blend(theme.accent, theme.accent_alt, model.anim.pulse(35_u64))),
            border_set: CryTUI::Widgets::BorderSet::THICK
          )
          lines = [
            centered("SIGNAL  #{slither(frame, 32)}", theme.accent),
            centered("LIQUID  #{liquid(frame, 32)}", theme.accent_alt),
            line(""),
            progress_line(model, frame, total),
            centered(boot_message(frame, total, model.show_icons), theme.muted),
          ]
          CryTUI::Widgets::StyledText.new(lines, block: block).render(rows[2], buffer)
        end

        private def live_line(model, frame)
          icon = model.show_icons ? ["◉", "●", "◍", "○"][(frame // 2 % 4).to_i] : ["o", "*", "o", "."][(frame // 2 % 4).to_i]
          centered("#{icon} LIVE CONTROL  ·  LOCAL IPC  ·  OBS STUDIO", model.theme.danger, true)
        end

        private def progress_line(model, frame, total)
          ratio = (frame.to_f64 / {total, 1_u64}.max).clamp(0.0, 1.0)
          filled = (ratio * 30).round.to_i
          full, empty = model.advanced_ui ? {"━", "─"} : {"#", "."}
          centered("[#{full * filled}#{empty * (30 - filled)}] #{(ratio * 100).round.to_i.to_s.rjust(3)}%", model.theme.info)
        end

        private def boot_message(frame, total, icons)
          progress = frame.to_f64 / {total, 1_u64}.max
          message = progress < 0.25 ? "loading terminal engine" : progress < 0.5 ? "negotiating local IPC" : progress < 0.75 ? "warming telemetry panels" : "broadcast control ready"
          "#{icons ? "◆" : ">"} #{message}"
        end

        private def slither(frame, width)
          Array.new(width) { |index| ((index - frame.to_i) % 12) < 4 ? "█" : "·" }.join
        end

        private def liquid(frame, width)
          bars = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
          Array.new(width) do |index|
            bars[((Math.sin(index * 0.55 + frame * 0.18) * 3.5 + 3.5).round.to_i).clamp(0, 7)]
          end.join
        end

        private def center(area, width, height)
          CryTUI::Rect.new(area.x + (area.width - width) // 2, area.y + (area.height - height) // 2, width, height)
        end

        private def centered(text, color, bold = false)
          modifiers = bold ? CryTUI::Modifier::Bold : CryTUI::Modifier::None
          CryTUI::Line.from(text, CryTUI::Style.new(foreground: color, modifiers: modifiers), CryTUI::Alignment::Center)
        end

        private def line(text)
          CryTUI::Line.from(text)
        end
      end
    end
  end
end
