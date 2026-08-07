require "./braille"

module CryTUI
  module Widgets
    # A dot on the braille grid a ring spinner walks.
    struct RingCoord
      getter row : Int32
      getter col : Int32

      def initialize(@row, @col)
      end
    end

    # The dot grid a ring arc is drawn into. `offset` shifts every row so a
    # shape that starts above the origin still lands inside the array; writes
    # that fall outside are dropped rather than wrapped.
    class RingGrid
      getter cells : Array(Array(Bool))
      getter offset : Int32

      def initialize(@cells : Array(Array(Bool)), @offset : Int32)
      end

      def set(row : Int32, col : Int32, value : Bool) : Nil
        r = row + @offset
        return if r < 0 || col < 0
        return if r >= @cells.size || col >= @cells[0].size
        @cells[r][col] = value
      end

      # Lights an L-shaped path: all the way along the row, then along the
      # column. Used once at build time to seed the spoke the arc unwinds from.
      def fill(start : RingCoord, finish : RingCoord) : Nil
        horizontal = finish.col < start.col ? -1 : 1
        vertical = finish.row < start.row ? -1 : 1
        row = start.row
        col = start.col
        set(row, col, true)
        while row != finish.row
          row += vertical
          set(row, col, true)
        end
        while col != finish.col
          col += horizontal
          set(row, col, true)
        end
      end
    end

    # The arc engine behind `SquareSpinner` and `RectSpinner`.
    #
    # A `size`-thick bar of dots (the head) walks the perimeter lighting cells
    # while a second bar (the tail) trails behind clearing them, so the lit
    # region is an arc chasing itself around the ring. Straight runs move the
    # bar one dot at a time; the corners are lookup tables that rotate the bar
    # from one edge onto the next.
    class RingEngine
      getter grid : RingGrid
      getter head : Array(RingCoord)
      getter tail : Array(RingCoord)
      getter? has_centre : Bool
      # `{{top row, left column}, {bottom row, right column}}` in character
      # cells, marking where the enclosed area starts and stops.
      @centre_bounds : Tuple(Tuple(Int32, Int32), Tuple(Int32, Int32))
      @head_map : Hash(RingCoord, RingCoord)
      @tail_map : Hash(RingCoord, RingCoord)

      # Dots across the ring for a given thickness. Both the width and the
      # height of the grid, since the shape is square.
      def self.dimension(size : Int32) : Int32
        8 + 5 * {size - 2, 0}.max
      end

      # The thinnest ring is two dot-rows short of a whole braille cell, so it
      # is pushed down to sit on the cell boundary instead of straddling it.
      def self.vertical_offset(size : Int32) : Int32
        size == 2 ? 2 : 0
      end

      def initialize(size : Int32, centre : Centre)
        size = size.clamp(2, 8)
        dimension = RingEngine.dimension(size)
        offset = RingEngine.vertical_offset(size)
        @grid = RingGrid.new(Array.new(dimension + offset) { Array.new(dimension, false) }, offset)

        centre_cells, centre_start, centre_end = RingEngine.centre_cells(size, dimension)
        # Recorded in character cells, not dots: the renderer flips colour when
        # it crosses these columns so the enclosed area reads as a separate
        # shape from the ring around it.
        @centre_bounds = {
          {(centre_start.row + offset) // 4, (centre_start.col // 2) - 1},
          {(centre_end.row + offset) // 4, centre_end.col // 2},
        }

        remainder = (dimension % 2) + ((size - 2) // 2)
        middle = (dimension // 2) + remainder
        @head = Array.new(size) { |dot| RingCoord.new(dot, middle) }
        @tail = Array.new(size) { |dot| RingCoord.new(middle, dot) }
        size.times { |index| @grid.fill(@tail[index], @head[index]) }

        @has_centre = centre.filled?
        centre_cells.each { |cell| @grid.set(cell.row, cell.col, true) } if @has_centre

        @head_map = RingEngine.head_map(dimension, dimension, size)
        @tail_map = RingEngine.tail_map(dimension, dimension, size)
      end

      # Replays `steps` walks, folding a long-running tick back into one
      # revolution.
      #
      # The widget is stateless -- every frame rebuilds the engine and replays
      # the whole tick -- so an hour-old TUI would otherwise pay an hour of
      # walks per frame. The walk is only periodic once the tail has cleared
      # the initial spoke, which is why the first revolution is always replayed
      # in full and only the remainder is folded.
      def advance(steps : UInt64) : Nil
        period = RingEngine.period(@head.size, @head_map).to_u64
        bounded = steps < period ? steps : period + (steps - period) % period
        bounded.times { walk }
      end

      def walk : Nil
        @head = RingEngine.step(@head, @head_map)
        @head.each { |position| @grid.set(position.row, position.col, true) }
        @tail.each { |position| @grid.set(position.row, position.col, false) }
        @tail = RingEngine.step(@tail, @tail_map)
      end

      def lines(arc_color : Color, dim_color : Color, alignment : Alignment) : Array(Line)
        rows = @grid.cells.size
        columns = @grid.cells[0].size
        char_rows = (rows + 3) // 4
        char_columns = (columns + 1) // 2
        screen = Array.new(char_rows) { Array.new(char_columns, 0_u8) }
        @grid.cells.each_with_index do |row_cells, row|
          row_cells.each_with_index do |lit, col|
            next unless lit
            screen[row // 4][col // 2] |= 1_u8 << Braille::MAP[row % 4][col % 2]
          end
        end

        active = arc_color
        screen.map_with_index do |row, y|
          spans = row.map_with_index do |byte, x|
            span = Span.new(Braille.char(byte), Style.new(foreground: active))
            active = active == arc_color ? dim_color : arc_color if @has_centre && switches_colour?(y, x)
            span
          end
          Line.new(spans, alignment)
        end
      end

      # The rendered size in character cells, so a caller can reserve space for
      # a spinner before drawing it.
      def self.char_size(size : Int32) : Tuple(Int32, Int32)
        size = size.clamp(2, 8)
        dimension = RingEngine.dimension(size)
        {(dimension + 1) // 2, (dimension + vertical_offset(size) + 3) // 4}
      end

      private def switches_colour?(row : Int32, col : Int32) : Bool
        top, bottom = @centre_bounds
        return false unless row >= top[0] && row <= bottom[0]
        col == top[1] || col == bottom[1]
      end

      # Walks a throwaway bar around the ring to find how many steps a full
      # revolution takes. Cheap enough to redo per frame -- the largest ring is
      # a few hundred steps -- and it keeps the period honest if the corner
      # tables ever change.
      def self.period(size : Int32, head_map : Hash(RingCoord, RingCoord)) : Int32
        dimension = RingEngine.dimension(size)
        middle = (dimension // 2) + (dimension % 2) + ((size - 2) // 2)
        start = Array.new(size) { |dot| RingCoord.new(dot, middle) }
        nodes = start
        limit = 8 * dimension
        (1..limit).each do |step|
          nodes = RingEngine.step(nodes, head_map)
          return step if nodes == start
        end
        limit
      end

      def self.centre_cells(size : Int32, width : Int32) : Tuple(Array(RingCoord), RingCoord, RingCoord)
        middle = width // 2
        offset = size // 2
        start = RingCoord.new(middle - offset, middle - offset)
        cells = [] of RingCoord
        size.times do |row|
          size.times { |col| cells << RingCoord.new(start.row + row, start.col + col) }
        end
        {cells, start, RingCoord.new(start.row + size - 1, start.col + size - 1)}
      end

      # Corner tables. Each entry rotates the bar off the edge it just finished
      # and onto the next one; anything not in the table is a straight run.
      def self.head_map(width : Int32, height : Int32, size : Int32) : Hash(RingCoord, RingCoord)
        map = {} of RingCoord => RingCoord
        last_col = width - 1
        last_row = height - 1
        size.times { |dot| map[RingCoord.new(dot, last_col)] = RingCoord.new(size, last_col - dot) }
        size.times { |dot| map[RingCoord.new(last_row, last_col - dot)] = RingCoord.new(last_row - dot, last_col - size) }
        size.times { |dot| map[RingCoord.new(last_row - dot, 0)] = RingCoord.new(last_col - size, dot) }
        size.times { |dot| map[RingCoord.new(0, dot)] = RingCoord.new(dot, size) }
        map
      end

      def self.tail_map(width : Int32, height : Int32, size : Int32) : Hash(RingCoord, RingCoord)
        map = {} of RingCoord => RingCoord
        last_col = width - 1
        last_row = height - 1
        size.times { |dot| map[RingCoord.new(size, dot)] = RingCoord.new(dot, 0) }
        size.times { |dot| map[RingCoord.new(dot, last_col - size)] = RingCoord.new(0, last_col - dot) }
        size.times { |dot| map[RingCoord.new(last_row - size, last_col - dot)] = RingCoord.new(last_row - dot, last_col) }
        size.times { |dot| map[RingCoord.new(last_row - dot, size)] = RingCoord.new(last_row, dot) }
        map
      end

      def self.step(nodes : Array(RingCoord), rotation : Hash(RingCoord, RingCoord)) : Array(RingCoord)
        if rotated = rotate(nodes, rotation)
          return rotated
        end
        moved = nodes
        # A bar standing in one column travels sideways; one lying in one row
        # travels up or down. Only one of the two can hold for a straight bar.
        if moved.all? { |node| node.col == moved[0].col }
          direction = moved.any? { |node| node.row == 0 } ? 1 : -1
          moved = moved.map { |node| RingCoord.new(node.row, node.col + direction) }
        end
        if moved.all? { |node| node.row == moved[0].row }
          direction = moved.any? { |node| node.col == 0 } ? -1 : 1
          moved = moved.map { |node| RingCoord.new(node.row + direction, node.col) }
        end
        moved
      end

      # A corner only turns when every dot of the bar is on it; a partially
      # entered corner keeps travelling straight.
      def self.rotate(nodes : Array(RingCoord), rotation : Hash(RingCoord, RingCoord)) : Array(RingCoord)?
        rotated = Array(RingCoord).new(nodes.size)
        nodes.each do |position|
          mapped = rotation[position]?
          return unless mapped
          rotated << mapped
        end
        rotated
      end
    end
  end
end
