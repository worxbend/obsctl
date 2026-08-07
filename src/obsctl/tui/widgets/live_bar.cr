require "./chrome"
require "../anim"

module Obsctl
  module TUI
    module Widgets
      module LiveBar
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          theme = model.theme
          active = model.streaming? || model.recording?
          pulse = model.anim.pulse(24_u64)
          border_color = if model.advanced_ui
                           Anim.blend(theme.border, active ? theme.danger : theme.info, pulse * (active ? 0.8 : 0.18))
                         else
                           theme.border
                         end
          title = model.advanced_ui ? Anim.gradient_line(" ◉ LIVE TELEMETRY ", theme.danger, theme.warning, model.anim.frame, true) : CryTUI::Line.from(" LIVE TELEMETRY ", CryTUI::Style.new(foreground: theme.danger, modifiers: CryTUI::Modifier::Bold))
          block = CryTUI::Widgets::Block.new(title: title, border_style: CryTUI::Style.new(foreground: border_color), border_set: model.advanced_ui ? CryTUI::Widgets::BorderSet::ROUNDED : CryTUI::Widgets::BorderSet::ASCII)
          if {area.height - 2, 0}.max < 2
            compact = CryTUI::Line.new([
              badge("LIVE", model.streaming?, model.stream_duration_ms, pulse, model), CryTUI::Span.new("  "),
              badge("REC", model.recording?, model.record_duration_ms, pulse, model), separator(model),
              compact_metrics(model),
            ])
            CryTUI::Widgets::StyledText.new([compact], block: block).render(area, buffer)
            return
          end
          first = CryTUI::Line.new([
            badge("LIVE", model.streaming?, model.stream_duration_ms, pulse, model), CryTUI::Span.new("  "),
            badge("REC", model.recording?, model.record_duration_ms, pulse, model), separator(model),
            CryTUI::Span.new("#{model.symbol("🎬", "SCN")} #{model.current_scene || "no active scene"}", CryTUI::Style.new(foreground: theme.foreground)),
          ].concat(transport_spans(model, active)))
          second = metrics_line(model)
          CryTUI::Widgets::StyledText.new([first, second], block: block).render(area, buffer)
        end

        # A glow running along the transport while something is being sent out.
        # Nothing is drawn when the output is idle, so the movement means
        # exactly one thing.
        private def transport_spans(model : Model, active : Bool) : Array(CryTUI::Span)
          return [] of CryTUI::Span unless active && model.advanced_ui

          spinner = CryTUI::Widgets::BarSpinner.new(
            model.anim.frame,
            motion: CryTUI::Widgets::BarMotion::Loop,
            arc_color: model.theme.danger,
            dim_color: model.theme.border,
            fade_width: 4
          )
          [separator(model)] + Anim.spans(spinner.lines(16))
        end

        private def compact_metrics(model : Model) : CryTUI::Span
          if stats = model.stats
            bitrate = model.stream_bitrate_kbps.try { |value| "#{value.round.to_i}kbps" } || "--kbps"
            text = "CPU #{stats.cpu_usage_percent.round(1)}%  FPS #{stats.active_fps.round(1)}  MEM #{stats.memory_usage_mb.round.to_i}MB  #{bitrate}"
            CryTUI::Span.new(text, CryTUI::Style.new(foreground: model.theme.info))
          else
            text = model.advanced_ui ? "telemetry waiting…" : "telemetry waiting..."
            CryTUI::Span.new(text, CryTUI::Style.new(foreground: model.theme.muted))
          end
        end

        private def badge(label : String, active : Bool, duration_ms : Int64?, pulse : Float64, model : Model) : CryTUI::Span
          if active
            dot = pulse > 0.5 ? model.symbol("●", "*") : model.symbol("◉", "*")
            color = Anim.blend(model.theme.danger, model.theme.warning, pulse * 0.45)
            CryTUI::Span.new(" #{dot} #{label} #{format_duration(duration_ms)} ", CryTUI::Style.new(foreground: color, modifiers: CryTUI::Modifier::Bold | CryTUI::Modifier::Reversed))
          else
            CryTUI::Span.new(" #{model.symbol("○", "-")} #{label} off ", CryTUI::Style.new(foreground: model.theme.muted))
          end
        end

        private def metrics_line(model : Model) : CryTUI::Line
          stats = model.stats
          unless stats
            return CryTUI::Line.new([
              CryTUI::Span.new("#{model.symbol("⌁", "~")} telemetry", CryTUI::Style.new(foreground: model.theme.info)),
              CryTUI::Span.new(model.advanced_ui ? "  waiting for OBS metrics…" : "  waiting for OBS metrics...", CryTUI::Style.new(foreground: model.theme.muted)),
            ])
          end

          graph = model.advanced_ui ? Anim.sparkline(model.cpu_history, 10) : Anim.sparkline_ascii(model.cpu_history, 10)
          bitrate_graph = model.advanced_ui ? Anim.sparkline(model.bitrate_history, 10) : Anim.sparkline_ascii(model.bitrate_history, 10)
          bitrate = model.stream_bitrate_kbps.try { |value| "#{value.round.to_i}kbps" } || "--kbps"
          CryTUI::Line.new([
            metric("CPU", "#{stats.cpu_usage_percent.round(1)}%", graph, model.theme.warning), separator(model),
            metric("FPS", stats.active_fps.round(1).to_s, "", model.theme.success), separator(model),
            metric("MEM", "#{stats.memory_usage_mb.round.to_i}MB", "", model.theme.info), separator(model),
            metric("NET", bitrate, bitrate_graph, model.theme.accent_alt),
          ])
        end

        private def metric(label : String, value : String, graph : String, color : CryTUI::Color) : CryTUI::Span
          suffix = graph.empty? ? "" : " #{graph}"
          CryTUI::Span.new("#{label} #{value}#{suffix}", CryTUI::Style.new(foreground: color, modifiers: CryTUI::Modifier::Bold))
        end

        private def format_duration(duration_ms : Int64?) : String
          return "--:--" unless duration_ms
          total_seconds = duration_ms // 1000
          hours = total_seconds // 3600
          minutes = (total_seconds % 3600) // 60
          seconds = total_seconds % 60
          hours > 0 ? "%02d:%02d:%02d" % {hours, minutes, seconds} : "%02d:%02d" % {minutes, seconds}
        end

        private def separator(model : Model) : CryTUI::Span
          CryTUI::Span.new(model.advanced_ui ? "  │  " : "  |  ", CryTUI::Style.new(foreground: model.theme.border))
        end
      end
    end
  end
end
