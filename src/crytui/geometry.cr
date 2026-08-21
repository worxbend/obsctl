require "kiwi"

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
      total = @direction.horizontal? ? area.width : area.height
      solve(total).map do |start, size|
        @direction.horizontal? ? Rect.new(area.x + start, area.y, size, area.height) : Rect.new(area.x, area.y + start, area.width, size)
      end
    end

    private REQUIRED = Kiwi::Strength::REQUIRED
    private STRONG   = Kiwi::Strength::STRONG
    private MEDIUM   = Kiwi::Strength::MEDIUM
    private WEAK     = Kiwi::Strength::WEAK

    private def solve(total : Int32) : Array(Tuple(Int32, Int32))
      if shortcut = closed_form(total)
        return shortcut
      end

      precision = 100.0
      scaled_total = total * precision
      count = @constraints.size
      variables = Array.new(count * 2 + 2) { |index| Kiwi::Variable.new("layout_#{index}") }
      solver = Kiwi::Solver.new
      constrain(solver, variables.first == 0, REQUIRED)
      constrain(solver, variables.last == scaled_total, REQUIRED)
      area_size = variables.last - variables.first
      variables.each do |variable|
        constrain(solver, variable >= variables.first, REQUIRED)
        constrain(solver, variable <= variables.last, REQUIRED)
      end
      # Ratatui only requires each segment to have a non-negative size.
      # Spacers are constrained separately and may be negative for overlap.
      variables.skip(1).each_slice(2) do |pair|
        constrain(solver, pair[0] <= pair[1], REQUIRED) if pair.size == 2
      end

      # Ratatui 0.29 defaults to Flex::Start: its leading spacer is empty,
      # internal spacers have the requested size, and unused room trails.
      constrain(solver, variables[1] == variables[0], REQUIRED - 1.0)
      (1...count).each do |index|
        constrain(solver, variables[index * 2 + 1] - variables[index * 2] == @spacing * precision, REQUIRED / 10.0)
      end
      constrain(solver, variables.last - variables[-2] == area_size, MEDIUM / 10.0)

      segments = @constraints.map_with_index { |_, index| {variables[index * 2 + 1], variables[index * 2 + 2]} }
      @constraints.each_with_index do |constraint, index|
        start, finish = segments[index]
        apply_constraint(solver, constraint, finish - start, area_size, precision)
      end

      apply_proportionality(solver, segments)

      solver.update_variables
      to_ranges(segments, precision)
    end

    # The three layouts whose sizes follow from arithmetic alone, so the
    # constraint solver never has to run. Returns nil when none applies.
    private def closed_form(total : Int32) : Array(Tuple(Int32, Int32))?
      if @spacing == 0 && @constraints.all?(&.kind.percentage?)
        return cumulative_ranges(total, @constraints.map { |constraint| constraint.value.to_f64 / 100.0 })
      end
      if @spacing == 0 && @constraints.all?(&.kind.ratio?)
        return cumulative_ranges(total, @constraints.map { |constraint| constraint.value.to_f64 / {constraint.denominator, 1}.max })
      end
      if @spacing >= 0 && @constraints.all?(&.kind.fill?)
        weights = @constraints.map { |constraint| {constraint.value, 1}.max.to_f64 }
        sum = weights.sum
        available = {total - @spacing * (@constraints.size - 1), 0}.max
        ranges = cumulative_ranges(available, weights.map { |weight| weight / sum })
        ranges.map_with_index { |(start, size), index| {start + index * @spacing, size} }
      end
    end

    # What one constraint asks of its own segment. The strengths are Ratatui's:
    # a length outranks a percentage, which outranks a ratio, and every kind
    # yields to the required structural constraints.
    private def apply_constraint(solver : Kiwi::Solver, constraint : Constraint, size : Kiwi::Expression, area_size : Kiwi::Expression, precision : Float64) : Nil
      case constraint.kind
      when .min?
        constrain(solver, size >= constraint.value * precision, STRONG * 100.0)
        constrain(solver, size == area_size, MEDIUM)
      when .max?
        constrain(solver, size <= constraint.value * precision, STRONG * 100.0)
        constrain(solver, size == constraint.value * precision, MEDIUM * 10.0)
      when .length?
        constrain(solver, size == constraint.value * precision, STRONG * 10.0)
      when .percentage?
        constrain(solver, size == area_size * constraint.value / 100.0, STRONG)
      when .ratio?
        denominator = {constraint.denominator, 1}.max
        constrain(solver, size == area_size * constraint.value / denominator, STRONG / 10.0)
      when .fill?
        constrain(solver, size == area_size, MEDIUM)
      end
    end

    # How the segments relate to each other: every pair of flexible segments
    # keeps its weight ratio, and, failing everything else, neighbours prefer
    # to come out the same size.
    private def apply_proportionality(solver : Kiwi::Solver, segments : Array(Tuple(Kiwi::Variable, Kiwi::Variable))) : Nil
      flexible = @constraints.each_with_index.select { |constraint, _| constraint.kind.fill? || constraint.kind.min? }.to_a
      flexible.each_combination(2) do |pair|
        left_constraint, left_index = pair[0]
        right_constraint, right_index = pair[1]
        left_weight = left_constraint.kind.fill? ? {left_constraint.value, 1}.max.to_f64 : 1.0
        right_weight = right_constraint.kind.fill? ? {right_constraint.value, 1}.max.to_f64 : 1.0
        left_start, left_finish = segments[left_index]
        right_start, right_finish = segments[right_index]
        constrain(solver, right_weight * (left_finish - left_start) == left_weight * (right_finish - right_start), MEDIUM / 10.0)
      end
      segments.each_cons(2) do |pair|
        left_start, left_finish = pair[0]
        right_start, right_finish = pair[1]
        constrain(solver, left_finish - left_start == right_finish - right_start, WEAK)
      end
    end

    # Back from the solver's fixed-point values to whole cells.
    private def to_ranges(segments : Array(Tuple(Kiwi::Variable, Kiwi::Variable)), precision : Float64) : Array(Tuple(Int32, Int32))
      segments.map do |start, finish|
        rounded_start = (start.value.round / precision).round.to_i
        rounded_finish = (finish.value.round / precision).round.to_i
        {rounded_start, {rounded_finish - rounded_start, 0}.max}
      end
    end

    private def cumulative_ranges(total : Int32, fractions : Array(Float64)) : Array(Tuple(Int32, Int32))
      cursor = 0
      cumulative = 0.0
      fractions.map do |fraction|
        cumulative += fraction
        finish = {round_half_up(total * cumulative), total}.min
        result = {cursor, {finish - cursor, 0}.max}
        cursor = finish
        result
      end
    end

    private def round_half_up(value : Float64) : Int32
      (value + 0.5).floor.to_i
    end

    private def constrain(solver : Kiwi::Solver, constraint : Kiwi::Constraint, strength : Float64)
      constraint.strength = strength
      solver.add_constraint(constraint)
    end
  end
end
