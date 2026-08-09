require "../../../crytui"
require "../model"
require "../anim"
require "./chrome"

module Obsctl
  module TUI
    module Widgets
      # What the beacon is reporting.
      #
      # Streaming while recording is a state of its own rather than two badges
      # competing for the same corner, which is why `Simulcast` exists instead
      # of a pair of booleans.
      enum BeaconMode
        Offline
        Idle
        Recording
        Streaming
        Simulcast
      end

      # The animated state light in the top-right corner of the header.
      #
      # Each mode is given a *motion* of its own, not just a colour: the corner
      # has to be readable out of the edge of an eye, and on a terminal whose
      # palette cannot be trusted colour alone says nothing. Nothing moves while
      # OBS is away, a lone marker drifts back and forth while idle, the bar
      # swells in place while recording, arcs run outwards from the centre while
      # streaming, and they chase in one direction when both outputs are live.
      module StatusBeacon
        extend self

        # Enough track to read a motion from, and the floor the shorter labels
        # round up to.
        MIN_WIDTH = 8
        # Columns left between the header text and the beacon.
        GAP = 2
        # The header text keeps at least this much. Below it the corner is not
        # worth what it would cost the status line.
        MIN_TEXT_WIDTH = 56
        # Cells in the plain-UI track. Odd, so the radiating pattern has a
        # centre to run out from.
        ASCII_WIDTH = 7

        def mode(model : Model) : BeaconMode
          return BeaconMode::Offline unless model.obs_connected?
          streaming = model.streaming?
          recording = model.recording?
          return BeaconMode::Simulcast if streaming && recording
          return BeaconMode::Streaming if streaming
          return BeaconMode::Recording if recording
          BeaconMode::Idle
        end

        # Columns the beacon needs. Only ever its own label, so an idle corner
        # does not charge the status line for the width an `ON AIR` timer would
        # have taken. The label is right-aligned in the column it asks for, so
        # what moves as the state changes is the far end of the track, not the
        # text the eye is reading.
        def width(model : Model) : Int32
          state = mode(model)
          {CryTUI::TextWidth.width(badge(state, model)), MIN_WIDTH}.max
        end

        # Splits the header's inner area into the text column and the beacon's,
        # or leaves the whole row to the text when the corner would not fit.
        def reserve(inner : CryTUI::Rect, model : Model) : Tuple(CryTUI::Rect, CryTUI::Rect?)
          columns = width(model)
          return {inner, nil} if inner.width < MIN_TEXT_WIDTH + GAP + columns

          text_width = inner.width - GAP - columns
          {
            CryTUI::Rect.new(inner.x, inner.y, text_width, inner.height),
            CryTUI::Rect.new(inner.x + text_width + GAP, inner.y, columns, inner.height),
          }
        end

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          return if area.empty?

          state = mode(model)
          # The label is the part that survives a one-row corner: it names the
          # state outright, where the track only implies it.
          lines = if area.height >= 2
                    [motion_line(area.width, state, model), label_line(state, model)]
                  else
                    [label_line(state, model)]
                  end
          CryTUI::Widgets::StyledText.new(lines).render(area, buffer)
        end

        private def motion_line(width : Int32, state : BeaconMode, model : Model) : CryTUI::Line
          return ascii_motion_line(state, model) unless model.advanced_ui
          return CryTUI::Line.new([CryTUI::Span.new("╌" * width, CryTUI::Style.new(foreground: model.theme.border))]) if state.offline?
          return breathing_line(width, model) if state.recording?

          spinner = CryTUI::Widgets::BarSpinner.new(
            model.anim.frame,
            motion: motion(state),
            arc_width: state.idle? ? 2 : 3,
            ticks_per_step: state.idle? ? 3_u64 : 1_u64,
            arc_color: accent(state, model),
            dim_color: model.theme.border,
            fade_width: 2
          )
          CryTUI::Line.new(Anim.spans(spinner.lines(width)))
        end

        # Recording is a steady state, so its track does not travel: every cell
        # runs the same density frame and the bar breathes where it stands.
        private def breathing_line(width : Int32, model : Model) : CryTUI::Line
          spinner = CryTUI::Widgets::FluxSpinner.new(
            model.anim.frame,
            width: width,
            color: Anim.blend(model.theme.border, model.theme.warning, model.anim.pulse(20_u64) * 0.85 + 0.15),
            ticks_per_step: 2_u64,
            phase_step: 0,
            frames: CryTUI::Widgets::FluxFrames::PULSE
          )
          CryTUI::Line.new(Anim.spans(spinner.lines))
        end

        private def motion(state : BeaconMode) : CryTUI::Widgets::BarMotion
          case state
          when .streaming? then CryTUI::Widgets::BarMotion::Radiate
          when .simulcast? then CryTUI::Widgets::BarMotion::Loop
          else                  CryTUI::Widgets::BarMotion::Bounce
          end
        end

        # The plain-UI track. `advanced_ui` off means braille is off the table,
        # so each mode keeps its cadence in ASCII instead of losing it.
        private def ascii_motion_line(state : BeaconMode, model : Model) : CryTUI::Line
          frame = model.anim.frame
          track = case state
                  in .offline?   then "-" * ASCII_WIDTH
                  in .idle?      then marked(bounce(frame // 3, ASCII_WIDTH), '*', '.')
                  in .recording? then Anim::ASCII_LEVELS[bounce(frame // 2, Anim::ASCII_LEVELS.size)].to_s * ASCII_WIDTH
                  in .streaming? then radiating(frame // 2)
                  in .simulcast? then marked(((frame // 2) % ASCII_WIDTH).to_i, '>', '-')
                  end
          CryTUI::Line.new([CryTUI::Span.new(track, CryTUI::Style.new(foreground: accent(state, model)))], CryTUI::Alignment::Right)
        end

        # Two markers walking out from the centre to the edges and starting
        # over, each pointing the way it travels.
        private def radiating(step : UInt64) : String
          centre = ASCII_WIDTH // 2
          offset = (step % (centre + 1)).to_i
          String.build do |io|
            ASCII_WIDTH.times { |index| io << radiating_cell(index - centre, offset) }
          end
        end

        private def radiating_cell(distance : Int32, offset : Int32) : Char
          return '.' unless distance.abs == offset
          return '*' if distance.zero?
          distance < 0 ? '<' : '>'
        end

        private def marked(index : Int32, lit : Char, track : Char) : String
          String.build do |io|
            ASCII_WIDTH.times { |cell| io << (cell == index ? lit : track) }
          end
        end

        # An index walking to the end of a row and back again.
        private def bounce(step : UInt64, size : Int32) : Int32
          return 0 if size <= 1
          cycle = 2 * (size - 1)
          position = (step % cycle).to_i
          position < size ? position : cycle - position
        end

        private def label_line(state : BeaconMode, model : Model) : CryTUI::Line
          style = CryTUI::Style.new(foreground: accent(state, model), modifiers: state.offline? ? CryTUI::Modifier::None : CryTUI::Modifier::Bold)
          CryTUI::Line.new([CryTUI::Span.new(badge(state, model), style)], CryTUI::Alignment::Right)
        end

        private def badge(state : BeaconMode, model : Model) : String
          "#{dot(state, model)} #{label(state, model)}"
        end

        private def dot(state : BeaconMode, model : Model) : String
          case state
          when .offline?   then model.symbol("○", "-")
          when .idle?      then model.symbol("◌", "o")
          when .recording? then model.symbol("●", "*")
          else                  model.symbol("◉", "*")
          end
        end

        # Deliberately untranslated, matching the `LIVE`/`REC` badges the live
        # bar already draws.
        private def label(state : BeaconMode, model : Model) : String
          case state
          in .offline?   then "OFFLINE"
          in .idle?      then "IDLE"
          in .recording? then "REC #{Chrome.duration(model.record_duration_ms)}"
          in .streaming? then "ON AIR #{Chrome.duration(model.stream_duration_ms)}"
          in .simulcast? then "LIVE+REC #{Chrome.duration(model.stream_duration_ms)}"
          end
        end

        private def accent(state : BeaconMode, model : Model) : CryTUI::Color
          theme = model.theme
          case state
          in .offline?   then theme.muted
          in .idle?      then theme.info
          in .recording? then theme.warning
          in .streaming? then theme.danger
          in .simulcast? then Anim.blend(theme.danger, theme.warning, model.anim.pulse(24_u64) * 0.5)
          end
        end
      end
    end
  end
end
