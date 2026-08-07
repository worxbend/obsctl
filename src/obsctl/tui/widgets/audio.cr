require "./chrome"
require "../anim"
require "../meter"
require "../layout"

module Obsctl
  module TUI
    module Widgets
      # The audio matrix, drawn the way a mixing desk is: one vertical channel
      # strip per input, each with its own meter, fader, readouts and mute
      # button, scrolling sideways when there are more inputs than columns.
      module Audio
        extend self

        # Eighth-height blocks, so a meter cell can be partly lit and the level
        # resolves to eight times the rows the panel actually has.
        FILL = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
        # Anything above this counts as signal for the panel's live indicator.
        SILENCE = 0.02

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          inputs = model.audio_inputs
          focused = model.focus.audio?
          block = Chrome.panel(icon(model, inputs), "Audio Matrix", hint(model, inputs[model.audio_cursor]?), inputs.size, focused, model)
          block.render(area, buffer)

          content = MixerLayout.inner(area)
          return if content.empty?
          if inputs.empty?
            buffer.set_string(content.x, content.y, "no audio inputs", CryTUI::Style.new(foreground: model.theme.muted), content.width)
            return
          end

          rows = MixerLayout.rows(area)
          MixerLayout.strips(inputs.size, model.audio_cursor, area).each do |index, strip|
            draw_strip(buffer, strip, rows, inputs[index], index == model.audio_cursor, focused, model)
          end
        end

        # A pulsing glyph while audio is actually moving, so the panel shows the
        # desk is live even when every strip is scrolled off.
        private def icon(model : Model, inputs : Array(OBS::State::AudioState)) : String
          live = model.advanced_ui && inputs.any? { |input| (model.meter_levels[input.name]? || 0.0) > SILENCE }
          return model.symbol("🎚", "A") unless live

          CryTUI::Widgets::FluxSpinner.new(
            model.anim.frame,
            frames: CryTUI::Widgets::FluxFrames::PULSE,
            ticks_per_step: 2_u64
          ).glyph
        end

        # Strips are too narrow for a full name, so the selected channel's
        # identity is spelled out in the panel title instead of truncated into
        # the column.
        private def hint(model : Model, input : OBS::State::AudioState?) : String
          keys = model.symbol("←/→ chan  ↑/↓ gain  m mute", "</> chan  ^/v gain  m mute")
          return "[a]  #{keys}" unless input

          detail = String.build do |io|
            io << input.name
            io << " (" << input.alias << ")" if input.alias
            io << " [" << input.shortcut << "]" if input.shortcut
          end
          "[a]  #{detail}  #{model.advanced_ui ? "·" : "-"}  #{keys}"
        end

        private def draw_strip(buffer, strip : CryTUI::Rect, rows : MixerRows, input : OBS::State::AudioState, selected : Bool, focused : Bool, model : Model)
          columns = MixerLayout.columns(strip)
          level = model.meter_levels[input.name]?
          fraction = level.try { |value| Meter.fraction(value) }
          muted = input.muted == true

          rows.name.try { |row| draw_name(buffer, strip, row, input, fraction, selected, focused, model) }
          draw_meter(buffer, strip, columns, rows, fraction, model.meter_peak(input.name), muted, model)
          draw_fader(buffer, strip, columns, rows, input.volume_percent, muted, model)
          rows.decibels.try { |row| draw_readout(buffer, strip, row, decibels_text(fraction, model), fraction, muted, model) }
          rows.value.try { |row| draw_gain(buffer, strip, row, input.volume_percent, muted, model) }
          rows.mute.try { |row| draw_mute(buffer, strip, row, input.muted, selected, model) }
        end

        private def draw_name(buffer, strip : CryTUI::Rect, row : Int32, input : OBS::State::AudioState, fraction : Float64?, selected : Bool, focused : Bool, model : Model)
          theme = model.theme
          # An alias exists to be short, so it wins whenever the real name
          # would be cut off anyway.
          label = input.alias.try { |short| short.size < input.name.size ? short : nil } || input.name
          style = if selected && focused
                    CryTUI::Style.new(foreground: theme.highlight_foreground, background: theme.highlight_background, modifiers: CryTUI::Modifier::Bold)
                  elsif selected
                    CryTUI::Style.new(foreground: theme.accent, modifiers: CryTUI::Modifier::Bold)
                  elsif input.muted == true
                    CryTUI::Style.new(foreground: theme.muted)
                  else
                    CryTUI::Style.new(foreground: theme.foreground)
                  end
          # A clipping channel takes its name back off the selection colours so
          # it is the one thing on the panel that is red.
          if fraction && Meter.fraction_decibels(fraction) >= Meter::CLIP_DB && model.advanced_ui
            style = CryTUI::Style.new(
              foreground: theme.background,
              background: Anim.blend(theme.danger, theme.warning, model.anim.pulse(8_u64)),
              modifiers: CryTUI::Modifier::Bold
            )
          end
          buffer.set_string(strip.x, row, centered(label, strip.width, model), style, strip.width)
        end

        private def draw_meter(buffer, strip : CryTUI::Rect, columns : MixerColumns, rows : MixerRows, fraction : Float64?, peak : Float64?, muted : Bool, model : Model)
          height = rows.meter_height
          return if height <= 0

          filled = (fraction || 0.0) * height
          peak_row = peak.try { |value| ((1.0 - value) * height).to_i.clamp(0, height - 1) }
          height.times do |offset|
            # Rows are drawn top down but the meter fills bottom up, so a cell's
            # share of the fill is measured from the far end.
            from_bottom = height - 1 - offset
            portion = (filled - from_bottom).clamp(0.0, 1.0)
            color = level_color((from_bottom + 1).to_f64 / height, muted, model)
            symbol, style = meter_cell(portion, color, muted, model)
            # The hold marker only earns a cell above the live fill; inside it
            # the marker would just hide the level it is holding for.
            if peak_row == offset && portion <= 0.0
              symbol = model.symbol("▔", "=")
              style = CryTUI::Style.new(foreground: muted ? model.theme.muted : color, modifiers: CryTUI::Modifier::Bold)
            end
            columns.meter_width.times do |offset_column|
              x = columns.meter + offset_column
              buffer.set_string(x, rows.meter_top + offset, symbol, style, 1) if x < strip.right
            end
          end
          draw_idle_meter(buffer, strip, columns, rows, model) unless fraction
        end

        # A channel that has never reported a level gets a searching dot down
        # the middle of an empty meter, so "no signal" cannot be mistaken for
        # the solid column a hot channel draws.
        private def draw_idle_meter(buffer, strip : CryTUI::Rect, columns : MixerColumns, rows : MixerRows, model : Model)
          return unless model.advanced_ui
          x = columns.meter + columns.meter_width // 2
          return if x >= strip.right

          CryTUI::Widgets::BarSpinner.new(
            model.anim.frame,
            orientation: CryTUI::Direction::Vertical,
            thickness: 1,
            arc_width: 1,
            motion: CryTUI::Widgets::BarMotion::Bounce,
            bar_style: CryTUI::Widgets::BarStyle::Dot,
            arc_color: Anim.blend(model.theme.border, model.theme.accent, 0.5),
            dim_color: model.theme.border,
            ticks_per_step: 2_u64
          ).render(CryTUI::Rect.new(x, rows.meter_top, 1, rows.meter_height), buffer)
        end

        private def meter_cell(portion : Float64, color : CryTUI::Color, muted : Bool, model : Model) : Tuple(String, CryTUI::Style)
          unless model.advanced_ui
            return {"#", CryTUI::Style.new(foreground: color)} if portion >= 1.0
            return {"+", CryTUI::Style.new(foreground: color)} if portion > 0.0
            return {".", CryTUI::Style.new(foreground: model.theme.border)}
          end

          if portion >= 1.0
            {"█", CryTUI::Style.new(foreground: color, modifiers: muted ? CryTUI::Modifier::Dim : CryTUI::Modifier::None)}
          elsif portion > 0.0
            {FILL[(portion * FILL.size).ceil.to_i.clamp(1, FILL.size) - 1].to_s, CryTUI::Style.new(foreground: color)}
          else
            # The unlit track keeps a ghost of the colour the cell would take,
            # which is what makes the scale readable while the channel is quiet.
            {"░", CryTUI::Style.new(foreground: Anim.blend(model.theme.border, color, 0.35))}
          end
        end

        # OBS' meter colours: green to -20 dBFS, yellow to -9, red above it.
        private def level_color(fraction : Float64, muted : Bool, model : Model) : CryTUI::Color
          theme = model.theme
          return theme.muted if muted

          db = Meter.fraction_decibels(fraction)
          return theme.danger if db > Meter::DANGER_DB
          return theme.warning if db > Meter::WARNING_DB
          return theme.success unless model.advanced_ui

          share = ((db - Meter::FLOOR_DB) / (Meter::WARNING_DB - Meter::FLOOR_DB)).clamp(0.0, 1.0)
          Anim.blend(theme.success, theme.warning, share * 0.45)
        end

        private def draw_fader(buffer, strip : CryTUI::Rect, columns : MixerColumns, rows : MixerRows, percent : Int32?, muted : Bool, model : Model)
          height = rows.meter_height
          return if height <= 0 || percent.nil? || columns.fader >= strip.right

          theme = model.theme
          handle = ((1.0 - percent.clamp(0, 100) / 100.0) * (height - 1)).round.to_i.clamp(0, height - 1)
          height.times do |offset|
            symbol, style = if offset == handle
                              {model.symbol("━", "="), CryTUI::Style.new(foreground: muted ? theme.muted : theme.accent, modifiers: CryTUI::Modifier::Bold)}
                            elsif offset > handle
                              {model.symbol("┃", "|"), CryTUI::Style.new(foreground: Anim.blend(theme.border, theme.accent, muted ? 0.15 : 0.6))}
                            else
                              {model.symbol("│", ":"), CryTUI::Style.new(foreground: theme.border)}
                            end
            buffer.set_string(columns.fader, rows.meter_top + offset, symbol, style, 1)
          end
        end

        private def draw_readout(buffer, strip : CryTUI::Rect, row : Int32, text : String, fraction : Float64?, muted : Bool, model : Model)
          color = if muted || fraction.nil?
                    model.theme.muted
                  else
                    level_color(fraction, false, model)
                  end
          buffer.set_string(strip.x, row, centered(text, strip.width, model), CryTUI::Style.new(foreground: color), strip.width)
        end

        # `-12.4 dB` is exactly the strip width, which is the reason the unit
        # fits at all -- and the reason it is dropped from the `-inf` case.
        private def decibels_text(fraction : Float64?, model : Model) : String
          return model.advanced_ui ? "–∞" : "-inf" unless fraction
          sprintf("%.1f dB", Meter.fraction_decibels(fraction))
        end

        private def draw_gain(buffer, strip : CryTUI::Rect, row : Int32, percent : Int32?, muted : Bool, model : Model)
          theme = model.theme
          text = percent ? "#{percent}%" : "--"
          style = CryTUI::Style.new(foreground: muted ? theme.muted : theme.info, modifiers: CryTUI::Modifier::Bold)
          buffer.set_string(strip.x, row, centered(text, strip.width, model), style, strip.width)
        end

        private def draw_mute(buffer, strip : CryTUI::Rect, row : Int32, muted : Bool?, selected : Bool, model : Model)
          theme = model.theme
          text, style = case muted
                        when true
                          {model.symbol("✖ MUTE", "MUTE"), CryTUI::Style.new(foreground: theme.danger, modifiers: CryTUI::Modifier::Bold | CryTUI::Modifier::Reversed)}
                        when false
                          {model.symbol("♪ LIVE", "LIVE"), CryTUI::Style.new(foreground: theme.success, modifiers: selected ? CryTUI::Modifier::Bold : CryTUI::Modifier::None)}
                        else
                          {"--", CryTUI::Style.new(foreground: theme.muted)}
                        end
          buffer.set_string(strip.x, row, centered(text, strip.width, model), style, strip.width)
        end

        # Pads to the full strip width so a highlighted row fills its column
        # rather than only the glyphs in it.
        private def centered(text : String, width : Int32, model : Model) : String
          return "" if width <= 0
          fitted = truncate(text, width, model.advanced_ui ? "…" : "~")
          padding = width - CryTUI::TextWidth.width(fitted)
          "#{" " * (padding // 2)}#{fitted}#{" " * (padding - padding // 2)}"
        end

        private def truncate(text : String, width : Int32, ellipsis : String) : String
          return text if CryTUI::TextWidth.width(text) <= width
          limit = width - CryTUI::TextWidth.width(ellipsis)
          return ellipsis[0, {width, 0}.max] if limit <= 0

          used = 0
          kept = String.build do |io|
            text.each_grapheme do |grapheme|
              symbol = grapheme.to_s
              size = CryTUI::TextWidth.grapheme_width(symbol)
              break if used + size > limit
              io << symbol
              used += size
            end
          end
          "#{kept}#{ellipsis}"
        end
      end
    end
  end
end
