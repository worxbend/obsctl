require "../../crytui"

module Obsctl
  module TUI
    module Anim
      extend self

      BARS         = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
      ASCII_LEVELS = ['.', '-', '=', '+', '*', '#']

      def blend(from : CryTUI::Color, to : CryTUI::Color, amount : Number) : CryTUI::Color
        return from unless from.kind.rgb? && to.kind.rgb?
        t = amount.to_f32.clamp(0.0_f32, 1.0_f32)
        CryTUI::Color.rgb(
          lerp(from.red, to.red, t),
          lerp(from.green, to.green, t),
          lerp(from.blue, to.blue, t)
        )
      end

      def gradient_line(text : String, from : CryTUI::Color, to : CryTUI::Color, frame : UInt64, bold = false, alignment = CryTUI::Alignment::Left) : CryTUI::Line
        width = {text.size, 1}.max.to_f32
        spans = text.each_char.map_with_index do |character, index|
          position = index.to_f32 / width
          wave = Math.sin(position * Math::TAU.to_f32 + frame.to_f32 * 0.12_f32)
          modifier = bold ? CryTUI::Modifier::Bold : CryTUI::Modifier::None
          CryTUI::Span.new(character.to_s, CryTUI::Style.new(foreground: blend(from, to, wave * 0.5 + 0.5), modifiers: modifier))
        end.to_a
        CryTUI::Line.new(spans, alignment)
      end

      def sparkline(values : Enumerable(Number), width : Int32) : String
        history(values, width, BARS, normalize_from_zero: true)
      end

      def sparkline_ascii(values : Enumerable(Number), width : Int32) : String
        history(values, width, ASCII_LEVELS, normalize_from_zero: false)
      end

      private def lerp(from : UInt8, to : UInt8, amount : Float32) : Int32
        (from + (to.to_i - from.to_i) * amount).round.to_i
      end

      private def history(values : Enumerable(Number), width : Int32, levels : Array(Char), normalize_from_zero : Bool) : String
        return "" if width <= 0
        samples = values.map(&.to_f64).to_a.last(width)
        return levels.first.to_s * width if samples.empty?
        minimum = normalize_from_zero ? 0.0 : samples.min
        maximum = {samples.max, normalize_from_zero ? 1.0 : samples.min + Float64::EPSILON}.max
        range = {maximum - minimum, Float64::EPSILON}.max
        String.build do |io|
          io << levels.first.to_s * (width - samples.size)
          samples.each do |sample|
            index = (((sample - minimum) / range).clamp(0.0, 1.0) * (levels.size - 1)).round.to_i
            io << levels[index]
          end
        end
      end
    end
  end
end
