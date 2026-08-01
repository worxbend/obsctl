require "../layout"
require "./header"
require "./live_bar"
require "./scenes"
require "./audio"
require "./profiles"
require "./collections"
require "./logs"
require "./stats"
require "./command_palette"

module Obsctl
  module TUI
    module Widgets
      module Dashboard
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          buffer.set_style(area, CryTUI::Style.new(background: model.theme.background, foreground: model.theme.foreground))
          # Stream health only earns a column of the logs row while there is a
          # stream to be healthy about.
          areas = DashboardLayout.compute(area, model.streaming?)
          Header.render(areas.header, buffer, model)
          LiveBar.render(areas.live_bar, buffer, model)
          Scenes.render(areas.scenes, buffer, model)
          Audio.render(areas.audio, buffer, model)
          Profiles.render(areas.profiles, buffer, model)
          Collections.render(areas.collections, buffer, model)
          Logs.render(areas.logs, buffer, model)
          areas.stats.try { |stats_area| Stats.render(stats_area, buffer, model) }
          CommandPalette.render(areas.palette, buffer, model)
        end
      end
    end
  end
end
