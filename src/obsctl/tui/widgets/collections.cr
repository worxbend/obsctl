require "./resource_list"

module Obsctl
  module TUI
    module Widgets
      module Collections
        extend self

        def render(area : CryTUI::Rect, buffer : CryTUI::Buffer, model : Model)
          ResourceList.render(area, buffer, model, model.scene_collections, model.current_scene_collection, model.collection_cursor, model.focus.collections?, model.symbol("🗂", "C"), "Collections", model.symbol("[c]  ↵ switch", "[c] Enter switch"))
        end
      end
    end
  end
end
