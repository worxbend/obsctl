require "../anim"

module Obsctl
  module TUI
    module Widgets
      module Splash
        extend self

        TAGLINE     = "Broadcast control, without breaking flow."
        DESCRIPTION = "Scenes, audio, profiles, recording, and live telemetry — one command center."
        LARGE_LOGO  = [
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
          pulse = (Math.sin(frame.to_f32 * 0.18_f32) * 0.5_f32 + 0.5_f32).clamp(0.0_f32, 1.0_f32)
          title = CryTUI::Line.new([
            CryTUI::Span.new(" #{orbit} ", CryTUI::Style.new(foreground: theme.warning)),
            CryTUI::Span.new("INITIALIZING BROADCAST CONTROL", CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new(" #{orbit} ", CryTUI::Style.new(foreground: theme.info)),
          ])
          block = CryTUI::Widgets::Block.new(
            title: title,
            border_style: CryTUI::Style.new(foreground: Anim.blend(theme.accent, theme.accent_alt, pulse)),
            border_set: CryTUI::Widgets::BorderSet::ROUNDED
          )
          lines = [
            line(""),
            Anim.gradient_line("◢ O B S C T L ◣", theme.accent, theme.accent_alt, frame, true, CryTUI::Alignment::Center),
            line(""),
            centered(TAGLINE, theme.foreground),
            live_line(model, frame),
          ]
          lines << centered("SYNC   #{slither(frame, 18)}", theme.info) if block.inner(area).height >= 7
          lines.concat([
            progress_line(model, frame, total),
            centered(boot_message(frame, total, model.show_icons), theme.muted),
          ])
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end

        private def render_ascii(area, buffer, model, frame, total)
          theme = model.theme
          block = CryTUI::Widgets::Block.new(title: " OBSCTL STARTUP ", border_style: CryTUI::Style.new(foreground: theme.accent), border_set: CryTUI::Widgets::BorderSet::ASCII)
          lines = ASCII_LOGO.map { |text| centered(text, theme.accent, true) }
          lines << centered(TAGLINE, theme.foreground)
          lines << centered("Scenes, audio, profiles, recording, and live telemetry.", theme.muted)
          spinner = ["|", "/", "-", "\\"][(frame // 2 % 4).to_i]
          lines << centered("#{spinner}  (o) LIVE  #{spinner}", theme.danger, true)
          lines << line("")
          ratio = progress(frame, total)
          filled = (ratio * 30).round.to_i
          lines << centered("[#{"#" * filled}#{"." * (30 - filled)}] #{(ratio * 100).round.to_i.to_s.rjust(3)}%", theme.info)
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
            centered(DESCRIPTION, theme.muted),
            live_line(model, frame),
          ]
          CryTUI::Widgets::StyledText.new(identity).render(rows[1], buffer)
          block = CryTUI::Widgets::Block.new(
            title: CryTUI::Line.from(" STUDIO LINK // SECURE SESSION ", CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold)),
            borders: CryTUI::Widgets::Borders::Left,
            style: CryTUI::Style.new(background: Anim.blend(theme.background, theme.border, 0.34)),
            border_style: CryTUI::Style.new(foreground: Anim.blend(theme.accent, theme.accent_alt, splash_pulse(frame))),
            border_set: CryTUI::Widgets::BorderSet::THICK
          )
          lines = [
            centered("SIGNAL #{slither(frame, 32)}", theme.accent),
            centered("LIQUID #{liquid(frame, 32)}", theme.accent_alt),
            line(""),
            progress_line(model, frame, total),
            centered(boot_message(frame, total, model.show_icons), theme.muted),
          ]
          CryTUI::Widgets::StyledText.new(lines, block: block).render(rows[2], buffer)
        end

        private def live_line(model, frame)
          phase = (frame // 2 % 4).to_i
          icon = model.show_icons ? ["◉", "●", "◍", "○"][phase] : ["O", "o", "O", "."][phase]
          wings = model.show_icons ? [{"⟫", "⟪"}, {"›", "‹"}, {"·", "·"}, {"›", "‹"}][phase] : [{">", "<"}, {"-", "-"}, {".", "."}, {"-", "-"}][phase]
          pulse = Math.sin(frame.to_f32 * 0.35_f32) * 0.5_f32 + 0.5_f32
          color = Anim.blend(model.theme.danger, model.theme.warning, pulse * 0.35)
          badge_style = if phase.even?
                          CryTUI::Style.new(foreground: model.theme.background, background: color, modifiers: CryTUI::Modifier::Bold)
                        else
                          CryTUI::Style.new(foreground: color, modifiers: CryTUI::Modifier::Bold)
                        end
          CryTUI::Line.new([
            CryTUI::Span.new("#{wings[0]}  ", CryTUI::Style.new(foreground: model.theme.muted)),
            CryTUI::Span.new(" #{icon}  LIVE ", badge_style),
            CryTUI::Span.new("  #{wings[1]}", CryTUI::Style.new(foreground: model.theme.muted)),
          ], CryTUI::Alignment::Center)
        end

        private def progress_line(model, frame, total)
          ratio = progress(frame, total)
          filled = (ratio * 30).round.to_i
          spans = [CryTUI::Span.new("  ")]
          30.times do |index|
            if index < filled
              color = Anim.blend(model.theme.accent, model.theme.accent_alt, index.to_f32 / 30.0_f32)
              spans << CryTUI::Span.new("█", CryTUI::Style.new(foreground: color))
            elsif index == filled
              spans << CryTUI::Span.new(frame.even? ? "▓" : "▒", CryTUI::Style.new(foreground: model.theme.info))
            else
              spans << CryTUI::Span.new("░", CryTUI::Style.new(foreground: model.theme.border))
            end
          end
          spans << CryTUI::Span.new("  #{(ratio * 100).round.to_i.to_s.rjust(3)}%", CryTUI::Style.new(foreground: model.theme.warning, modifiers: CryTUI::Modifier::Bold))
          CryTUI::Line.new(spans, CryTUI::Alignment::Center)
        end

        private def boot_message(frame, total, icons)
          ratio = progress(frame, total)
          icon, message = if ratio < 0.25
                            {"◌", "loading control surfaces"}
                          elsif ratio < 0.5
                            {"◍", "warming animation engine"}
                          elsif ratio < 0.75
                            {"◉", "syncing OBS telemetry"}
                          elsif ratio < 1.0
                            {"◎", "painting command center"}
                          else
                            {"✓", "ready"}
                          end
          icons ? "#{icon}  #{message}" : "[..] #{message}"
        end

        private def slither(frame, width)
          cells = Array.new(width, '·')
          return "" if width == 0
          head = frame.to_i % width
          ['█', '▓', '▒', '░'].each_with_index { |glyph, offset| cells[(head + width - offset) % width] = glyph }
          cells.join
        end

        private def liquid(frame, width)
          bars = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
          Array.new(width) do |index|
            phase = index.to_f32 * 0.62_f32 + frame.to_f32 * 0.32_f32
            bars[((Math.sin(phase) * 0.5_f32 + 0.5_f32) * 7.0_f32).round.to_i.clamp(0, 7)]
          end.join
        end

        private def progress(frame, total) : Float32
          (frame.to_f32 / {total, 1_u64}.max.to_f32).clamp(0.0_f32, 1.0_f32)
        end

        private def splash_pulse(frame) : Float32
          (Math.sin(frame.to_f32 * 0.18_f32) * 0.5_f32 + 0.5_f32).clamp(0.0_f32, 1.0_f32)
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
