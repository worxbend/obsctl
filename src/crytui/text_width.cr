module CryTUI
  # Terminal display-width helpers. Crystal supplies Unicode 17 grapheme
  # segmentation; CryTUI classifies each grapheme as zero, one, or two cells.
  # Ambiguous-width characters intentionally default to one cell, matching
  # Ratatui and most UTF-8 terminal configurations.
  module TextWidth
    extend self

    def width(text : String) : Int32
      text.each_grapheme.sum { |grapheme| grapheme_width(grapheme.to_s) }
    end

    def grapheme_width(grapheme : String) : Int32
      first = grapheme.each_char.first?
      return 0 unless first
      property = String::Grapheme::Property.from(first)
      return 0 if property.control? || property.cr? || property.lf? || property.extend? || property.zwj?
      return 2 if property.extended_pictographic? || property.regional_indicator?
      wide_codepoint?(first.ord) ? 2 : 1
    end

    # Derived from the Unicode EastAsianWidth W/F ranges. The broad astral
    # range includes assigned emoji and CJK extensions; unassigned codepoints
    # are harmless because they cannot occur in valid application text.
    private def wide_codepoint?(codepoint : Int32) : Bool
      codepoint >= 0x1100 && (
        codepoint <= 0x115F ||
          codepoint == 0x2329 || codepoint == 0x232A ||
          (0x2E80..0x303E).includes?(codepoint) ||
          (0x3040..0xA4CF).includes?(codepoint) ||
          (0xAC00..0xD7A3).includes?(codepoint) ||
          (0xF900..0xFAFF).includes?(codepoint) ||
          (0xFE10..0xFE19).includes?(codepoint) ||
          (0xFE30..0xFE6F).includes?(codepoint) ||
          (0xFF00..0xFF60).includes?(codepoint) ||
          (0xFFE0..0xFFE6).includes?(codepoint) ||
          (0x1F000..0x1FAFF).includes?(codepoint) ||
          (0x20000..0x3FFFD).includes?(codepoint)
      )
    end
  end
end
