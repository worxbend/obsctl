require "./resource_list"

module Obsctl
  module TUI
    module Widgets
      module Profiles
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          ResourceList.render(area, buffer, model, model.profiles, model.current_profile, model.profile_cursor, model.focus.profiles?, model.symbol("🎛", "P"), "Profiles", model.symbol("[p]  ↵ switch", "[p]  Enter switch"))
        end
      end
    end
  end
end
