require "./chrome"
require "../anim"

module Obsctl
  module TUI
    module Widgets
      # Live stream health, rendered beside the logs while streaming.
      #
      # Every value comes from the `GetStats` sample the daemon already polls
      # for the telemetry bar, so the panel costs no extra OBS traffic and
      # cannot disagree with the numbers in `LIVE TELEMETRY`.
      module Stats
        extend self

        # OBS's own stats dock treats a dropped-frame ratio under 1% as healthy
        # and 5% as the point where viewers see it.
        WARNING_DROP_PERCENT = 1.0
        DANGER_DROP_PERCENT  = 5.0

        # Share of one frame's budget spent rendering. Past half the budget OBS
        # is a single hiccup away from missing the next frame.
        WARNING_BUDGET_RATIO = 0.5
        DANGER_BUDGET_RATIO  = 0.8

        # FPS is judged against the best rate seen this session rather than a
        # fixed 60, so a 30 fps profile reads as healthy at 30.
        HEALTHY_FPS_RATIO = 0.95
        WARNING_FPS_RATIO =  0.8

        # Below this inner width the `skipped / total` columns stop fitting, so
        # the rows fall back to abbreviated labels and drop the sparkline.
        WIDE_INNER_WIDTH = 44

        FPS_GRAPH_WIDTH = 8

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          stats = model.stats
          dropped = stats ? stats.render_skipped_frames + stats.output_skipped_frames : 0_i64
          block = Chrome.panel(
            model.symbol("📊", "S"), "Stats", "dropped frames",
            dropped.clamp(0_i64, Int32::MAX.to_i64).to_i32, false, model
          )
          lines = stats ? metric_lines(stats, model, block.inner(area).width) : [waiting_line(model)]
          CryTUI::Widgets::StyledText.new(lines, block: block).render(area, buffer)
        end

        private def metric_lines(stats : OBS::State::ObsStats, model : Model, width : Int32) : Array(CryTUI::Line)
          wide = width >= WIDE_INNER_WIDTH
          [
            fps_line(stats, model, wide),
            frame_line(model, wide, wide ? "RENDER missed" : "render", stats.render_skipped_frames, stats.render_total_frames),
            frame_line(model, wide, wide ? "OUTPUT skipped" : "output", stats.output_skipped_frames, stats.output_total_frames),
            health_line(stats, model, wide),
          ]
        end

        private def waiting_line(model : Model) : CryTUI::Line
          CryTUI::Line.new([
            CryTUI::Span.new(" #{model.symbol("⌁", "~")} ", CryTUI::Style.new(foreground: model.theme.info)),
            CryTUI::Span.new(
              model.advanced_ui ? "waiting for OBS telemetry…" : "waiting for OBS telemetry...",
              CryTUI::Style.new(foreground: model.theme.muted)
            ),
          ])
        end

        private def fps_line(stats : OBS::State::ObsStats, model : Model, wide : Bool) : CryTUI::Line
          budget = frame_budget_ratio(stats)
          spans = [
            CryTUI::Span.new(" #{model.symbol("⚡", "F")} ", CryTUI::Style.new(foreground: model.theme.accent)),
            CryTUI::Span.new("%.2f" % stats.active_fps, CryTUI::Style.new(foreground: fps_color(stats, model), modifiers: CryTUI::Modifier::Bold)),
            CryTUI::Span.new(" fps", CryTUI::Style.new(foreground: model.theme.muted)),
          ]
          if wide && model.fps_history.size > 1
            graph = model.advanced_ui ? Anim.sparkline(model.fps_history, FPS_GRAPH_WIDTH) : Anim.sparkline_ascii(model.fps_history, FPS_GRAPH_WIDTH)
            spans << CryTUI::Span.new("  #{graph}", CryTUI::Style.new(foreground: model.theme.accent_alt))
          end
          spans << CryTUI::Span.new("  #{model.symbol("⏱", "T")} ", CryTUI::Style.new(foreground: model.theme.muted))
          spans << CryTUI::Span.new("#{"%.2f" % stats.average_frame_render_time_ms} ms", CryTUI::Style.new(foreground: budget_color(budget, model), modifiers: CryTUI::Modifier::Bold))
          CryTUI::Line.new(spans)
        end

        private def frame_line(model : Model, wide : Bool, label : String, skipped : Int64, total : Int64) : CryTUI::Line
          percent = drop_percent(skipped, total)
          value = wide ? "#{skipped.format} / #{total.format}" : skipped.format
          CryTUI::Line.new([
            CryTUI::Span.new(" #{model.symbol("▸", ">")} ", CryTUI::Style.new(foreground: model.theme.border)),
            CryTUI::Span.new(label.ljust(wide ? 15 : 7), CryTUI::Style.new(foreground: model.theme.muted)),
            CryTUI::Span.new(value.rjust(wide ? 15 : 6), CryTUI::Style.new(foreground: model.theme.foreground)),
            CryTUI::Span.new("  #{format_percent(percent).rjust(6)}", CryTUI::Style.new(
              foreground: percent ? severity_color(drop_severity(percent), model) : model.theme.muted,
              modifiers: CryTUI::Modifier::Bold
            )),
          ])
        end

        private def health_line(stats : OBS::State::ObsStats, model : Model, wide : Bool) : CryTUI::Line
          budget = frame_budget_ratio(stats)
          worst = {
            drop_severity(drop_percent(stats.render_skipped_frames, stats.render_total_frames)),
            drop_severity(drop_percent(stats.output_skipped_frames, stats.output_total_frames)),
            budget_severity(budget),
          }.max
          color = severity_color(worst, model)
          spans = [
            CryTUI::Span.new(" #{model.symbol("◆", "*")} ", CryTUI::Style.new(foreground: color)),
            CryTUI::Span.new((wide ? "HEALTH" : "health").ljust(wide ? 15 : 7), CryTUI::Style.new(foreground: model.theme.muted)),
            CryTUI::Span.new(verdict(worst), CryTUI::Style.new(foreground: color, modifiers: CryTUI::Modifier::Bold)),
          ]
          if wide && budget
            spans << CryTUI::Span.new(
              "  #{model.symbol("·", "-")} budget #{(budget * 100).round.to_i}%",
              CryTUI::Style.new(foreground: budget_color(budget, model))
            )
          end
          CryTUI::Line.new(spans)
        end

        # Milliseconds spent rendering a frame as a share of the time one frame
        # is allowed at the current rate. Nil until OBS reports a live rate.
        private def frame_budget_ratio(stats : OBS::State::ObsStats) : Float64?
          return unless stats.active_fps > 0.0
          stats.average_frame_render_time_ms / (1000.0 / stats.active_fps)
        end

        # Nil rather than zero before OBS has composited any frame, so an idle
        # counter is not rendered as a perfect score.
        private def drop_percent(skipped : Int64, total : Int64) : Float64?
          return unless total > 0
          skipped.to_f64 / total.to_f64 * 100.0
        end

        private def drop_severity(percent : Float64?) : Int32
          return 0 unless percent
          return 2 if percent >= DANGER_DROP_PERCENT
          percent >= WARNING_DROP_PERCENT ? 1 : 0
        end

        private def budget_severity(ratio : Float64?) : Int32
          return 0 unless ratio
          return 2 if ratio >= DANGER_BUDGET_RATIO
          ratio >= WARNING_BUDGET_RATIO ? 1 : 0
        end

        private def severity_color(severity : Int32, model : Model) : CryTUI::Color
          case severity
          when 0 then model.theme.success
          when 1 then model.theme.warning
          else        model.theme.danger
          end
        end

        private def verdict(severity : Int32) : String
          case severity
          when 0 then "nominal"
          when 1 then "degraded"
          else        "critical"
          end
        end

        private def budget_color(ratio : Float64?, model : Model) : CryTUI::Color
          return model.theme.muted unless ratio
          severity = budget_severity(ratio)
          severity.zero? ? model.theme.info : severity_color(severity, model)
        end

        private def fps_color(stats : OBS::State::ObsStats, model : Model) : CryTUI::Color
          reference = {model.fps_history.max? || stats.active_fps, stats.active_fps}.max
          return model.theme.muted unless reference > 0.0
          ratio = stats.active_fps / reference
          return model.theme.success if ratio >= HEALTHY_FPS_RATIO
          ratio >= WARNING_FPS_RATIO ? model.theme.warning : model.theme.danger
        end

        private def format_percent(percent : Float64?) : String
          percent ? "#{"%.2f" % percent}%" : "--"
        end
      end
    end
  end
end
