require "../theme"
require "./view"

module Obsctl
  module TUI
    # The theme, the display preferences, and the settings view's own state.
    #
    # Grouped because they change together: the settings view exists to
    # preview `theme` against `theme_preview_origin`, and `show_icons` /
    # `advanced_ui` are the same kind of answer as the theme -- how the
    # dashboard paints, not what it shows.
    class SettingsState
      property theme : Theme
      property show_icons : Bool
      property advanced_ui : Bool
      property command_palette_prefix : String
      property locale : String
      property view : View
      property settings_cursor : Int32
      property theme_preview_origin : Theme?

      def initialize(@theme = Theme.default, @show_icons = true, @advanced_ui = true, @command_palette_prefix = "/", @locale = "en")
        @view = View::Main
        @settings_cursor = 0
        @theme_preview_origin = nil
      end

      def rich_ui? : Bool
        @show_icons && @advanced_ui
      end

      def symbol(rich : String, fallback : String) : String
        rich_ui? ? rich : fallback
      end
    end
  end
end
