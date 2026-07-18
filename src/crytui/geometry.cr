module CryTUI
  enum Direction
    Horizontal
    Vertical
  end

  struct Rect
    getter x : Int32
    getter y : Int32
    getter width : Int32
    getter height : Int32

    def initialize(@x = 0, @y = 0, @width = 0, @height = 0)
      @width = @width.clamp(0, Int32::MAX)
      @height = @height.clamp(0, Int32::MAX)
    end

    def left : Int32
      @x
    end

    def top : Int32
      @y
    end

    def right : Int32
      @x + @width
    end

    def bottom : Int32
      @y + @height
    end

    def empty? : Bool
      @width == 0 || @height == 0
    end

    def inner(margin : Int32) : Rect
      amount = margin.clamp(0, {@width // 2, @height // 2}.min)
      Rect.new(@x + amount, @y + amount, @width - amount * 2, @height - amount * 2)
    end

    def intersection(other : Rect) : Rect
      x = {@x, other.x}.max
      y = {@y, other.y}.max
      Rect.new(x, y, {right, other.right}.min - x, {bottom, other.bottom}.min - y)
    end
  end

  enum ConstraintKind
    Length
    Min
    Max
    Percentage
    Ratio
    Fill
  end

  struct Constraint
    getter kind : ConstraintKind
    getter value : Int32
    getter denominator : Int32

    private def initialize(@kind, @value, @denominator = 1)
    end

    def self.length(value)
      new(ConstraintKind::Length, value.to_i)
    end

    def self.min(value)
      new(ConstraintKind::Min, value.to_i)
    end

    def self.max(value)
      new(ConstraintKind::Max, value.to_i)
    end

    def self.percentage(value)
      new(ConstraintKind::Percentage, value.to_i)
    end

    def self.ratio(numerator, denominator)
      new(ConstraintKind::Ratio, numerator.to_i, denominator.to_i)
    end

    def self.fill(weight = 1)
      new(ConstraintKind::Fill, weight.to_i)
    end
  end

  class Layout
    property direction : Direction
    property constraints : Array(Constraint)
    property spacing : Int32

    def initialize(@direction = Direction::Horizontal, @constraints = [] of Constraint, @spacing = 0)
    end

    def split(area : Rect) : Array(Rect)
      return [] of Rect if @constraints.empty?
      available = (@direction.horizontal? ? area.width : area.height) - @spacing * (@constraints.size - 1)
      available = available.clamp(0, Int32::MAX)
      sizes = allocate(available)
      cursor = @direction.horizontal? ? area.x : area.y
      sizes.map do |size|
        rect = @direction.horizontal? ? Rect.new(cursor, area.y, size, area.height) : Rect.new(area.x, cursor, area.width, size)
        cursor += size + @spacing
        rect
      end
    end

    private def allocate(total : Int32) : Array(Int32)
      sizes = Array(Int32).new(@constraints.size, 0)
      flexible = [] of Int32
      @constraints.each_with_index do |constraint, index|
        sizes[index] = case constraint.kind
                       when .length?     then constraint.value
                       when .percentage? then total * constraint.value.clamp(0, 100) // 100
                       when .ratio?      then constraint.denominator > 0 ? total * constraint.value // constraint.denominator : 0
                       when .min?        then constraint.value
                       else                   0
                       end
        flexible << index if constraint.kind.min? || constraint.kind.max? || constraint.kind.fill?
      end
      used = sizes.sum
      remaining = (total - used).clamp(0, Int32::MAX)
      weights = flexible.sum { |i| @constraints[i].kind.fill? ? @constraints[i].value.clamp(1, Int32::MAX) : 1 }
      flexible.each_with_index do |index, position|
        share = position == flexible.size - 1 ? remaining : remaining * (@constraints[index].kind.fill? ? @constraints[index].value.clamp(1, Int32::MAX) : 1) // weights
        sizes[index] += share
        remaining -= share
        weights -= @constraints[index].kind.fill? ? @constraints[index].value.clamp(1, Int32::MAX) : 1
        sizes[index] = {sizes[index], @constraints[index].value}.min if @constraints[index].kind.max?
      end
      overflow = sizes.sum - total
      sizes.reverse_each.with_index do |size, reverse_index|
        break if overflow <= 0
        index = sizes.size - reverse_index - 1
        reduction = {size, overflow}.min
        sizes[index] -= reduction
        overflow -= reduction
      end
      sizes
    end
  end
end
