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

      # Rasterises a dot grid into braille cell bytes: one byte per character
      # cell, with the block deciding whether each (row, col) dot is set. Lives
      # here so every spinner shares one copy of the cell-dimension arithmetic
      # and the `MAP` bit packing instead of reimplementing it per widget.
      def self.pack(dot_rows : Int32, dot_cols : Int32, & : Int32, Int32 -> Bool) : Array(Array(UInt8))
        grid = Array.new((dot_rows + 3) // 4) { Array.new((dot_cols + 1) // 2, 0_u8) }
        dot_rows.times do |row|
          dot_cols.times do |col|
            next unless yield row, col
            grid[row // 4][col // 2] |= 1_u8 << MAP[row % 4][col % 2]
          end
        end
        grid
      end
    end

    # The render tail every spinner shares: base style across the whole area,
    # the optional block, then one line per row of the current frame.
    module SpinnerBody
      def self.render(area : Rect, buffer : Buffer, style : Style, block : Block?, lines : Array(Line)) : Nil
        render(area, buffer, style, block) { lines }
      end

      # Spinners whose frame depends on how much room is left inside the block
      # -- a bar as wide as the content, a column as tall as it -- receive the
      # content rect and build their lines from it.
      def self.render(area : Rect, buffer : Buffer, style : Style, block : Block?, &lines : Rect -> Array(Line)) : Nil
        return if area.empty?
        buffer.set_style(area, style)
        content = Block.frame(block, area, buffer)
        return if content.empty?
        lines.call(content).first(content.height).each_with_index do |line, index|
          line.render(buffer, Rect.new(content.x, content.y + index, content.width, 1), style)
        end
      end
    end
  end
end
