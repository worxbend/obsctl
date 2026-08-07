require "../style"
require "../text"
require "../geometry"
require "../buffer"
require "../widgets"

module CryTUI
  module Widgets
    # Rotation direction, shared by every spinner that walks a ring or sweeps a
    # bar. Counter-clockwise reverses both the walk and, for multi-cell
    # spinners, the direction the phase wave travels.
    enum Spin
      Clockwise
      CounterClockwise
    end

    # Whether a ring spinner paints its enclosed area or leaves it blank.
    enum Centre
      Filled
      Empty
    end

    # One braille character carries a 2x4 dot matrix. `MAP[row % 4][col % 2]`
    # is the bit a dot lights, and the code point is `BASE` plus the resulting
    # byte -- which is why every ring spinner rasterises into a dot grid four
    # times taller and twice wider than the cells it finally occupies.
    module Braille
      BASE = 0x2800
      MAP  = [
        [0_u8, 3_u8],
        [1_u8, 4_u8],
        [2_u8, 5_u8],
        [6_u8, 7_u8],
      ]

      def self.char(byte : UInt8) : String
        (BASE + byte).chr.to_s
      end
    end

    # The render tail every spinner shares: base style across the whole area,
    # the optional block, then one line per row of the current frame.
    module SpinnerBody
      def self.render(area : Rect, buffer : Buffer, style : Style, block : Block?, lines : Array(Line)) : Nil
        return if area.empty?
        buffer.set_style(area, style)
        content = area
        if block
          block.render(area, buffer)
          content = block.inner(area)
        end
        return if content.empty?
        lines.first(content.height).each_with_index do |line, index|
          line.render(buffer, Rect.new(content.x, content.y + index, content.width, 1), style)
        end
      end
    end
  end
end
