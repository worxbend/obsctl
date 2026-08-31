require "crytui"
require "./layout"
require "./model"
require "./scene_picker"
require "./scene_profile_list"

module Obsctl
  module TUI
    # The scene picker overlay: a centred box listing every scene beside the
    # key that switches to it.
    #
    # Centred rather than anchored to the scenes panel because it is a modal --
    # while it is open nothing else takes keys, so putting it in the middle of
    # the screen says so. Shared with the hit test, the same way every other
    # overlay's geometry is, so a click resolves against the row that was
    # actually painted.
    module ScenePickerLayout
      extend self

      MIN_WIDTH = 24
      # Long scene names are truncated by the list rather than allowed to push
      # the box out to the full width of a wide terminal.
      MAX_WIDTH = 64
      # A border row above and below, so the box is this much taller than the
      # rows it can show.
      CHROME_HEIGHT = 2
      # Below this the box would show one scene at most, which is worse than
      # leaving the dashboard alone and saying nothing.
      MIN_HEIGHT = 5

      # Takes the model rather than a scene list so the title it measures is
      # built by the same code the widget draws, which is what stops the box
      # from being sized to something other than what it renders.
      def compute(area : CryTUI::Rect, model : Model) : CryTUI::Rect
        entries = model.scene_picker_entries
        return CryTUI::Rect.new(area.x, area.y, 0, 0) if entries.empty?

        widest = entries.max_of { |entry| CryTUI::TextWidth.width(row_text(entry)) }
        # Widened to the title as well as to the rows: a picker whose scene
        # names are all short would otherwise be too narrow to print its own
        # "esc close" hint, which is the only way out of a modal.
        # Both get `+ 2` for the border cell either side, which is the space
        # the block takes before any of its content is drawn.
        title = CryTUI::TextWidth.width(title_parts(model, entries.size).join)
        wanted = {widest + 2, title + 2, MIN_WIDTH}.max
        CenteredModal.center(area, wanted, entries.size, CHROME_HEIGHT, MIN_WIDTH, MAX_WIDTH, MIN_HEIGHT)
      end

      # The title in the three pieces the widget styles separately: heading,
      # scene count, key hint. They concatenate to exactly what `compute`
      # measured.
      def title_parts(model : Model, count : Int32) : Tuple(String, String, String)
        {
          " #{model.symbol("🎬", "S")}  Switch scene ",
          " #{count.to_s.rjust(2, '0')} ",
          "  #{model.symbol("↵ switch · esc close", "Enter switch  Esc close")} ",
        }
      end

      # One picker row. The widget splits this into styled spans that
      # concatenate back to exactly this string, so the width measured here is
      # the width that gets drawn.
      #
      # Unlabelled scenes keep the same indent as labelled ones so the names
      # stay in one column.
      def row_text(entry : ScenePicker::Entry) : String
        " #{entry.label || ' '}  #{entry.scene.name} "
      end
    end

    # The scene-profile editor overlay: every scene the daemon reported, hidden
    # ones included, because this is the one surface that can bring a hidden
    # scene back.
    #
    # Centred and shared with the hit test for the same reasons
    # `ScenePickerLayout` is: it is a modal, so the middle of the screen says
    # so, and a click has to resolve against the row that was actually painted.
    module SceneProfilesLayout
      extend self

      # Wider than the picker's floor because the rows carry a hide marker as
      # well as a scene name.
      MIN_WIDTH = 28
      # Long scene names are truncated by the list rather than allowed to push
      # the box out to the full width of a wide terminal. Wider than the
      # picker's floor because the hint row spells out five keys rather than
      # one.
      MAX_WIDTH = 72
      # A border row above and below, plus the row the hints keep for
      # themselves, so the box is this much taller than the rows it can show.
      CHROME_HEIGHT = 3
      # Below this the box would show two scenes at most, which is worse than
      # leaving the dashboard alone and saying nothing.
      MIN_HEIGHT = 6

      # Takes the model rather than a scene list so the title it measures is
      # built by the same code the widget draws, which is what stops the box
      # from being sized to something other than what it renders.
      def compute(area : CryTUI::Rect, model : Model) : CryTUI::Rect
        scenes = model.all_scenes
        return CryTUI::Rect.new(area.x, area.y, 0, 0) if scenes.empty?

        widest = scenes.max_of { |scene| CryTUI::TextWidth.width(row_text(model, scene)) }
        # Widened to the title and to the hint row as well as to the rows, so a
        # profile whose scene names are all short still has room for the keys
        # that are the only way out of a modal. Each gets `+ 2` for the border
        # cell either side.
        #
        # The title is measured at the widest the box may end up, because that
        # is the most room the name it carries can be given; a narrower box
        # fits the name to what it actually has (see `title_parts`).
        title = CryTUI::TextWidth.width(title_parts(model).join)
        hints = CryTUI::TextWidth.width(hint_text(model))
        wanted = {widest + 2, title + 2, hints + 2, MIN_WIDTH}.max
        CenteredModal.center(area, wanted, scenes.size, CHROME_HEIGHT, MIN_WIDTH, MAX_WIDTH, MIN_HEIGHT)
      end

      # Shared with the list modal next door; see `CenteredModal` for why
      # these are boxes rather than inner rows.
      def list_area(rect : CryTUI::Rect) : CryTUI::Rect
        CenteredModal.list_area(rect)
      end

      def hint_row(rect : CryTUI::Rect) : Int32
        CenteredModal.hint_row(rect)
      end

      # Every key the editor answers to, on a row of its own under the list.
      #
      # They are not in the title because the title carries the profile's name,
      # which is text the reader typed and can be any length. Sharing one line
      # with it meant the block silently cut the end off, and the end is where
      # "esc close" -- the only way out of the modal -- was. A row of its own is
      # also what makes room to mention the keys that cycle between saved
      # profiles, which is the whole point of having more than one.
      #
      # `width` is the box the row has to fit in. A terminal too narrow for the
      # full row gets a shorter one that still names a key and what it does,
      # rather than the full row with its tail cut off.
      def hint_text(model : Model, width : Int32 = MAX_WIDTH) : String
        return model.symbol(" ↵ confirm · esc cancel ", " Enter confirm  Esc cancel ") if model.scene_profile_editor.naming

        # "load profile", not "switch profile": Tab pulls a saved profile into the
        # draft being edited here, which is not the same as changing which one
        # the dashboard filters by -- that is what the list behind <leader>p
        # does, and calling both of them "switch" over-promised this one.
        full = model.symbol(
          " t hide · n name · ⇥ load profile · ↵ save · esc close ",
          " t hide  n name  Tab load profile  Enter save  Esc close "
        )
        return full if CryTUI::TextWidth.width(full) <= width - 2

        model.symbol(" t hide · ↵ save · esc close ", " t hide  Enter save  Esc close ")
      end

      # The title in the two pieces the widget styles separately: the heading
      # and the draft's name. They concatenate to exactly what `compute`
      # measured.
      #
      # `width` is the box the title has to fit in. The name is fitted to
      # whatever the heading leaves of it rather than allowed to run past the
      # border, because a block clips its title without saying so and the name
      # is unbounded: nothing stops a reader typing sixty characters.
      #
      # While a name is being typed the name piece becomes the input line, so
      # the box is always measured around what is actually drawn on it rather
      # than around the wider of two states.
      def title_parts(model : Model, width : Int32 = MAX_WIDTH) : Tuple(String, String)
        text = heading(model)
        {text, name_part(model, width - 2 - CryTUI::TextWidth.width(text))}
      end

      # One editor row. The widget splits this into styled spans that
      # concatenate back to exactly this string, so the width measured here is
      # the width that gets drawn.
      def row_text(model : Model, scene : OBS::State::SceneState) : String
        " #{marker(model, model.scene_profile_editor.hidden.includes?(scene.name))}  #{scene.name} "
      end

      # The hide state is carried by a marker as well as by the widget's
      # dimming, because a terminal that ignores the dim attribute would
      # otherwise draw hidden and visible scenes identically.
      #
      # Both markers are one cell wide, so toggling a scene never changes the
      # width the box was measured against.
      def marker(model : Model, hidden : Bool) : String
        hidden ? model.symbol("○", "-") : model.symbol("●", "+")
      end

      # "Edit profile", not "Scene profiles": the list modal next door is the one
      # called "Scene profiles", and two modals under the same title would leave
      # a reader unable to tell which of them they are looking at.
      private def heading(model : Model) : String
        " #{model.symbol("🗂", "P")}  Edit profile "
      end

      # The name badge, or the line being typed while one is being entered,
      # fitted into the `room` cells the heading left over. A box too narrow to
      # show a name at all drops the badge rather than the border.
      private def name_part(model : Model, room : Int32) : String
        return "" if room <= 2

        editor = model.scene_profile_editor
        return naming_part(model, editor, room) if editor.naming

        " #{CryTUI::TextWidth.truncate(editor.name.empty? ? "unnamed" : editor.name, room - 2, ellipsis(model))} "
      end

      # The typed name is followed by a block so the caret is visible where the
      # terminal's own cursor is not: the dashboard parks that in the corner.
      #
      # What scrolls out of a full field is the beginning, not the end: the
      # caret has to stay on screen or the reader is typing blind, with nothing
      # on the display changing as they do.
      private def naming_part(model : Model, editor : SceneProfileEditorState, room : Int32) : String
        prompt = " #{model.symbol("❯", ">")} "
        typed = "#{editor.name_input}#{model.advanced_ui ? "█" : "_"}"
        field = CryTUI::TextWidth.truncate_start(typed, room - CryTUI::TextWidth.width(prompt) - 1, ellipsis(model))
        "#{prompt}#{field} "
      end

      private def ellipsis(model : Model) : String
        model.symbol("…", "~")
      end
    end

    # The scene-profile list overlay: "show every scene" first, then every saved
    # profile, with the one in effect marked.
    #
    # Centred and shared with the hit test for the same reasons
    # `ScenePickerLayout` is: it is a modal, so the middle of the screen says
    # so, and a click has to resolve against the row that was actually painted.
    module SceneProfileListLayout
      extend self

      # Wider than the picker's floor because a row carries a label, a marker,
      # a name and the count of scenes that name hides.
      MIN_WIDTH = 30
      # Long profile names are truncated by the list rather than allowed to push
      # the box out to the full width of a wide terminal. The same ceiling the
      # editor uses, because the two modals open onto each other and a box that
      # jumped width between them would read as a different overlay.
      MAX_WIDTH = 72
      # A border row above and below, plus the row the hints keep for
      # themselves, so the box is this much taller than the rows it can show.
      CHROME_HEIGHT = 3
      # Below this the box would show two rows at most -- "show every scene"
      # and one profile -- which is worse than leaving the dashboard alone and
      # saying nothing.
      MIN_HEIGHT = 6

      # Takes the model rather than an entry list so the title it measures is
      # built by the same code the widget draws, which is what stops the box
      # from being sized to something other than what it renders.
      def compute(area : CryTUI::Rect, model : Model) : CryTUI::Rect
        entries = model.scene_profile_list_entries
        return CryTUI::Rect.new(area.x, area.y, 0, 0) if entries.empty?

        widest = entries.max_of { |entry| CryTUI::TextWidth.width(row_text(model, entry)) }
        # Widened to the title and to the hint row as well as to the rows, so a
        # list whose profile names are all short still has room for the keys
        # that are the only way out of a modal. Each gets `+ 2` for the border
        # cell either side, which is the space the block takes before any of
        # its content is drawn.
        #
        # Measured against the browsing hints even while a delete is armed:
        # arming one must not resize the box, or the row the reader is about to
        # press a second time moves out from under the pointer.
        title = CryTUI::TextWidth.width(title_parts(model, entries.size).join)
        hints = CryTUI::TextWidth.width(browsing_hint_text(model, MAX_WIDTH))
        wanted = {widest + 2, title + 2, hints + 2, MIN_WIDTH}.max
        CenteredModal.center(area, wanted, entries.size, CHROME_HEIGHT, MIN_WIDTH, MAX_WIDTH, MIN_HEIGHT)
      end

      # Shared with the editor modal next door; see `CenteredModal` for why
      # these are boxes rather than inner rows.
      def list_area(rect : CryTUI::Rect) : CryTUI::Rect
        CenteredModal.list_area(rect)
      end

      def hint_row(rect : CryTUI::Rect) : Int32
        CenteredModal.hint_row(rect)
      end

      # The title in the three pieces the widget styles separately: heading,
      # row count, key hint -- they concatenate to exactly what `compute`
      # measured. Unlike the editor's title this carries no user-typed text, so
      # the keys can share the line; the hint row below still spells out the
      # verbs, which are what a reader is looking for.
      def title_parts(model : Model, count : Int32) : Tuple(String, String, String)
        {
          " #{model.symbol("🗂", "P")}  Scene profiles ",
          " #{count.to_s.rjust(2, '0')} ",
          "  #{model.symbol("↵ use · esc close", "Enter use  Esc close")} ",
        }
      end

      # Every key the list answers to, on a row of its own under the rows.
      #
      # While a delete is armed the row becomes the question instead, because
      # the second press is the only thing between the reader and a profile that
      # cannot be brought back -- so the row that would have listed five keys
      # names the one profile at stake and the two keys that decide it.
      #
      # `width` is the box the row has to fit in; a terminal too narrow for the
      # full row gets a shorter one that still names a key and what it does,
      # rather than the full row with its tail cut off.
      def hint_text(model : Model, width : Int32 = MAX_WIDTH) : String
        return confirm_text(model, width) if model.scene_profile_list.confirming

        browsing_hint_text(model, width)
      end

      # One row. The widget splits this into styled spans that concatenate back
      # to exactly this string, so the width measured here is the width drawn.
      #
      # Both markers are one cell wide, so which row is in effect never changes
      # the width the box was measured against. The hidden-scene count is what
      # tells two similarly named profiles apart at a glance.
      def row_text(model : Model, entry : SceneProfileList::Entry) : String
        " #{entry.label || ' '}  #{marker(model, entry.active)}  #{entry.name}#{count_suffix(model, entry)} "
      end

      # The row in effect carries a marker as well as the widget's colouring,
      # because a terminal that ignores colour would otherwise draw the active
      # profile and the rest identically. The same pair the scenes panel already
      # uses for the live scene, so one shape means "this is the one" wherever
      # it appears.
      def marker(model : Model, active : Bool) : String
        active ? model.symbol("▶", ">") : model.symbol("◇", " ")
      end

      # How many scenes a profile keeps out of the list. Nothing for the "show
      # every scene" row, which hides nothing by definition and would read as a
      # profile that happens to hide zero.
      def count_suffix(model : Model, entry : SceneProfileList::Entry) : String
        profile = entry.profile
        return "" unless profile

        model.symbol(" · hides #{profile.hidden.size}", " - hides #{profile.hidden.size}")
      end

      private def browsing_hint_text(model : Model, width : Int32) : String
        full = model.symbol(
          " ↵ use · e edit · r rename · n new · d delete · esc close ",
          " Enter use  e edit  r rename  n new  d delete  Esc close "
        )
        return full if CryTUI::TextWidth.width(full) <= width - 2

        model.symbol(" ↵ use · e edit · esc close ", " Enter use  e edit  Esc close ")
      end

      # The name is fitted to what the question leaves rather than allowed to
      # run past the border, for the same reason the editor's title fits its
      # name: a profile name is text the reader typed and can be any length, and
      # the end of this row is where "esc cancel" is -- the only way to call
      # off a delete.
      private def confirm_text(model : Model, width : Int32) : String
        entries = model.scene_profile_list_entries
        name = entries[model.scene_profile_list.cursor]?.try(&.name) || ""
        opening, closing = model.rich_ui? ? {"“", "”"} : {"'", "'"}
        keys = model.symbol("? · d confirm · esc cancel ", "? d confirm  Esc cancel ")
        room = width - 2 - CryTUI::TextWidth.width(" delete #{opening}#{closing}#{keys}")
        fitted = CryTUI::TextWidth.truncate(name, {room, 1}.max, model.symbol("…", "~"))
        " delete #{opening}#{fitted}#{closing}#{keys}"
      end
    end
  end
end
