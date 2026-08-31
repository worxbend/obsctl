require "../domain/command_parser"
require "../ipc/command_name"
require "./completion"
require "./input"
require "./layout"
require "./session"

module Obsctl
  module TUI
    record ActionOutcome,
      quit : Bool = false,
      retry_subscription : Bool = false,
      message : String? = nil do
      # "I handled this action and have nothing to say about it."
      #
      # The dispatch chain uses nil to mean "not mine, try the next handler",
      # so an empty outcome is not the absence of an answer -- it is an answer
      # that ends the chain and leaves the status line alone.
      HANDLED = new
    end

    class Dispatcher
      VOLUME_DEBOUNCE = 120.milliseconds

      alias Sender = Proc(IPC::CommandPayload, IPC::Response)
      alias ThemePersister = Proc(Theme, String)
      alias Viewport = Proc(CryTUI::Rect)

      # Half-page steps need to know how tall the focused panel is. The area is
      # read through a proc rather than stored because it changes with every
      # resize, and asking at the moment of the keypress is what keeps the step
      # matched to what is on screen.
      DEFAULT_PAGE_STEP = 5

      def initialize(
        @model : Model,
        @sender : Sender,
        @theme_persister : ThemePersister? = nil,
        @volume_debounce : Time::Span = VOLUME_DEBOUNCE,
        @viewport : Viewport? = nil,
      )
        @volume_versions = Hash(String, UInt64).new(0_u64)
      end

      # Actions that only move focus or the cursor, with no daemon round trip.
      FOCUS_ACTIONS = {
        ActionKind::FocusScenes      => ->(model : Model) { model.focus = FocusPanel::Scenes },
        ActionKind::FocusAudio       => ->(model : Model) { model.focus = FocusPanel::Audio },
        ActionKind::FocusProfiles    => ->(model : Model) { model.focus = FocusPanel::Profiles },
        ActionKind::FocusCollections => ->(model : Model) { model.focus = FocusPanel::Collections },
        ActionKind::FocusPaneLeft    => ->(model : Model) { model.focus = model.focus.left },
        ActionKind::FocusPaneRight   => ->(model : Model) { model.focus = model.focus.right },
        ActionKind::FocusPaneUp      => ->(model : Model) { model.focus = model.focus.up },
        ActionKind::FocusPaneDown    => ->(model : Model) { model.focus = model.focus.down },
      }

      # Every action ends the sequence that produced it; only a fresh prefix
      # leaves one pending. Clearing here rather than in each branch is what
      # guarantees the which-key menu closes on whatever the next key does.
      def handle(action : Action) : ActionOutcome
        outcome = dispatch(action)
        @model.pending_sequence = action.kind.pending_sequence? ? (action.sequence || "") : ""
        outcome
      end

      private def dispatch(action : Action) : ActionOutcome
        return ActionOutcome::HANDLED if action.kind.pending_sequence? || action.kind.clear_sequence?

        if move = FOCUS_ACTIONS[action.kind]?
          move.call(@model)
          return ActionOutcome::HANDLED
        end

        pointer_action(action) ||
          palette_action(action) ||
          scene_picker_action(action) ||
          scene_profile_list_action(action) ||
          scene_profile_manage_action(action) ||
          scene_profiles_action(action) ||
          scene_profile_name_action(action) ||
          navigation_action(action) ||
          settings_action(action) ||
          command_action(action) ||
          ActionOutcome::HANDLED
      end

      private def scene_picker_action(action : Action) : ActionOutcome?
        case action.kind
        when .open_scene_picker?
          # Refusing to open on an empty list rather than showing an empty box:
          # the picker swallows every key while it is open, so a picker with
          # nothing to pick would be a dead end with no visible reason.
          return ActionOutcome.new(message: "no scenes to switch to") if @model.scenes.empty?

          # Opens on the scene that is live, so the cursor starts where the eye
          # already is instead of at the top of the list.
          @model.scene_picker_cursor = @model.scenes.index(&.active) || 0
          @model.scene_picker_active = true
          ActionOutcome::HANDLED
        when .close_scene_picker?
          @model.scene_picker_active = false
          ActionOutcome::HANDLED
        when .scene_picker_navigate_up?
          @model.scene_picker_cursor = {@model.scene_picker_cursor - 1, 0}.max
          ActionOutcome::HANDLED
        when .scene_picker_navigate_down?
          @model.scene_picker_cursor = {@model.scene_picker_cursor + 1, {@model.scenes.size - 1, 0}.max}.min
          ActionOutcome::HANDLED
        when .scene_picker_activate?
          switch_scene(@model.scene_picker_cursor)
        when .pick_scene?
          index = action.index
          index ? switch_scene(index) : ActionOutcome::HANDLED
        end
      end

      # Closes the picker and sends the switch.
      #
      # The dashboard's own scene cursor is moved to match, so the panel
      # underneath agrees with what was just picked and a later Enter on the
      # scenes panel repeats the same switch rather than a stale one.
      private def switch_scene(index : Int32) : ActionOutcome
        @model.scene_picker_active = false
        scene = @model.scenes[index]?
        return ActionOutcome::HANDLED unless scene

        @model.scene_cursor = index
        target_command(IPC::CommandName::SET_SCENE, scene.name)
      end

      # The scene-profile list: which saved profile is in effect.
      #
      # Nothing here talks to the daemon -- the daemon keeps reporting every
      # scene and this only changes which of them the dashboard draws. Unlike
      # the editor, every branch here takes effect at once and is written to
      # the config file at once: there is no draft to throw away, so there is
      # nothing for an Esc to undo.
      private def scene_profile_list_action(action : Action) : ActionOutcome?
        list = @model.scene_profile_list
        case action.kind
        when .open_scene_profile_list?
          # Opening on the row that is in effect, so the cursor starts where the
          # eye already is. Unlike the picker this never refuses to open: with
          # no profiles saved the list still has its "show every scene" row and
          # its `n` key, which is how a first profile gets made.
          list.cursor = @model.scene_profile_list_entries.index(&.active) || 0
          list.confirming = false
          list.active = true
          ActionOutcome::HANDLED
        when .close_scene_profile_list?
          list.active = false
          list.confirming = false
          ActionOutcome::HANDLED
        when .scene_profile_list_navigate_up?
          list.cursor = {list.cursor - 1, 0}.max
          ActionOutcome::HANDLED
        when .scene_profile_list_navigate_down?
          list.cursor = {list.cursor + 1, {@model.scene_profile_list_entries.size - 1, 0}.max}.min
          ActionOutcome::HANDLED
        when .scene_profile_list_activate?
          activate_scene_profile(list.cursor)
        when .pick_scene_profile?
          index = action.index
          index ? activate_scene_profile(index) : ActionOutcome::HANDLED
        end
      end

      # Shown instead of opening the scene-profile editor when the daemon has
      # not reported any scenes yet.
      NO_SCENES_TO_CONFIGURE = "no scenes to configure"

      # Puts a row into effect, closes the list, and writes the config file.
      #
      # Written immediately rather than on close, because activating is the
      # whole action -- there is nothing else the user could still decide, and a
      # profile that vanished on restart would look like the dashboard forgot.
      # Row 0 is "show every scene", which is `activate(nil)`: the config keeps
      # every saved profile and stops naming one.
      private def activate_scene_profile(index : Int32) : ActionOutcome
        entry = @model.scene_profile_list_entries[index]?
        return ActionOutcome::HANDLED unless entry

        @model.scene_profile_list.active = false
        # Only asks. The scene list changes when the daemon pushes the snapshot
        # this produces, and `Model#snapshot=` is what keeps the cursors on the
        # scenes they were on across that change -- doing it here would run
        # before the list had changed and re-seek nothing.
        profile = entry.profile
        return command(IPC::CommandPayload.new(name: IPC::CommandName::SET_SCENE_PROFILE, target: profile.name)) if profile

        command(IPC::CommandPayload.new(name: IPC::CommandName::CLEAR_SCENE_PROFILE))
      end

      # Editing, creating and deleting from the list. Split from
      # `scene_profile_list_action` because the two together are more branches
      # than ameba's complexity ratchet allows in one method -- the same split
      # the editor's two sub-modes already needed.
      private def scene_profile_manage_action(action : Action) : ActionOutcome?
        case action.kind
        when .scene_profile_list_edit?   then edit_selected_scene_profile(naming: false)
        when .scene_profile_list_rename? then edit_selected_scene_profile(naming: true)
        when .scene_profile_list_new?
          return ActionOutcome.new(message: NO_SCENES_TO_CONFIGURE) unless open_scene_profile_editor(profile: nil)

          ActionOutcome.new(message: "new scene profile: toggle scenes, then n to name it")
        when .scene_profile_list_delete_prompt?
          entry = selected_scene_profile_entry
          return ActionOutcome.new(message: "'#{SceneProfileList::SHOW_EVERY_SCENE}' is not a profile, so there is nothing to delete") unless entry && entry.profile

          @model.scene_profile_list.confirming = true
          # Said out loud as well as shown on the hint row, because a delete
          # cannot be undone and the second press is the only thing standing
          # between the user and losing the profile.
          ActionOutcome.new(message: "delete scene profile '#{entry.name}'? press d again to confirm")
        when .scene_profile_list_delete_cancel?
          @model.scene_profile_list.confirming = false
          ActionOutcome.new(message: "delete cancelled")
        when .scene_profile_list_delete_confirm?
          delete_selected_scene_profile
        end
      end

      private def selected_scene_profile_entry : SceneProfileList::Entry?
        @model.scene_profile_list_entries[@model.scene_profile_list.cursor]?
      end

      # Hands a saved profile to the editor, optionally with the name field
      # already open so a rename is one keystroke rather than two.
      #
      # The list closes on the way: both modals capture every key, so exactly
      # one of them may be open or the editor would silently swallow every key
      # meant for the list drawn underneath it.
      private def edit_selected_scene_profile(naming : Bool) : ActionOutcome
        entry = selected_scene_profile_entry
        profile = entry.try(&.profile)
        return ActionOutcome.new(message: "'#{SceneProfileList::SHOW_EVERY_SCENE}' is not a profile, so there is nothing to edit") unless entry && profile

        return ActionOutcome.new(message: NO_SCENES_TO_CONFIGURE) unless open_scene_profile_editor(profile: profile)

        if naming
          @model.scene_profile_editor.naming = true
          # Seeded with the current name rather than blank: while the name
          # field is open it takes the place of the title badge, so an empty
          # field would mean retyping the name with the old one nowhere on
          # screen. `n` inside the editor still starts from blank -- that one
          # is naming a fresh draft, not correcting an existing name.
          @model.scene_profile_editor.name_input = profile.name
        end
        ActionOutcome.new(message: naming ? "rename scene profile: #{entry.name}" : "editing scene profile: #{entry.name}")
      end

      private def delete_selected_scene_profile : ActionOutcome
        entry = selected_scene_profile_entry
        return ActionOutcome::HANDLED unless entry && entry.profile

        @model.scene_profile_list.confirming = false
        command(IPC::CommandPayload.new(name: IPC::CommandName::DELETE_SCENE_PROFILE, target: entry.name))
      end

      # The scene-profile editor: obsctl's own named sets of scenes to keep out
      # of the scene list.
      #
      # Nothing here talks to the daemon. Every branch edits the draft on the
      # model, and only `save_scene_profile` makes the draft the list the
      # dashboard draws -- which is what lets Esc throw an edit away.
      #
      # Split from `scene_profile_name_action` because the two sub-modes
      # together are more branches than ameba's complexity ratchet allows in
      # one method.
      private def scene_profiles_action(action : Action) : ActionOutcome?
        editor = @model.scene_profile_editor
        case action.kind
        when .open_scene_profiles?
          # Refusing to open on an empty list rather than showing an empty box:
          # the editor swallows every key while it is open, so it would be a
          # dead end with no visible reason.
          return ActionOutcome.new(message: NO_SCENES_TO_CONFIGURE) unless open_scene_profile_editor

          ActionOutcome::HANDLED
        when .close_scene_profiles?
          editor.active = false
          editor.naming = false
          # Said out loud, because the draft is thrown away here and the only
          # evidence otherwise would be the scene list not changing.
          ActionOutcome.new(message: "scene profile editing cancelled")
        when .scene_profiles_navigate_up?
          editor.cursor = {editor.cursor - 1, 0}.max
          ActionOutcome::HANDLED
        when .scene_profiles_navigate_down?
          editor.cursor = {editor.cursor + 1, {@model.all_scenes.size - 1, 0}.max}.min
          ActionOutcome::HANDLED
        when .scene_profiles_toggle_scene?
          toggle_scene_profile_scene(action.index)
        when .scene_profiles_cycle_next?     then cycle_scene_profile(1)
        when .scene_profiles_cycle_previous? then cycle_scene_profile(-1)
        when .scene_profiles_begin_naming?
          editor.naming = true
          editor.name_input = ""
          ActionOutcome::HANDLED
        when .scene_profiles_save?
          # An unnamed draft cannot be saved, so Enter asks for the name
          # instead of failing: toggle first and name afterwards is the flow
          # this supports.
          if editor.name.empty?
            editor.naming = true
            editor.name_input = ""
            return ActionOutcome.new(message: "name this scene profile")
          end

          save_scene_profile(editor.name)
        end
      end

      # Opens the editor on a saved profile, defaulting to whichever one is in
      # effect. `nil` is a deliberate argument, not an absent one: it is how
      # the list's `n` asks for a fresh draft instead of the active profile.
      # Returns false without opening anything when there are no scenes to
      # show. The editor captures every key while it is open and draws nothing
      # at all for an empty scene list, so opening it then would leave the
      # dashboard looking frozen with no visible reason. Every caller has to
      # answer for that, not just the `<leader>P` one.
      private def open_scene_profile_editor(profile : SceneProfile? = @model.scene_profiles.active_profile) : Bool
        return false if @model.all_scenes.empty?

        editor = @model.scene_profile_editor
        # Both modals capture every key, so exactly one of them may be open --
        # two overlays drawn on top of each other would leave the editor
        # silently answering keys aimed at the list.
        @model.scene_profile_list.active = false
        @model.scene_profile_list.confirming = false
        editor.name = profile.try(&.name) || ""
        # The saved profile the draft came from, so saving it under a different
        # name renames that profile rather than leaving a copy beside it.
        editor.origin_name = profile.try(&.name)
        # A brand-new draft starts from what is on screen right now, so a user
        # adopting profiles for the first time cannot open the editor, save,
        # and watch the scene list change under them.
        #
        # Unless a profile is already in effect: the daemon resolves an active
        # profile *into* those `hidden` flags, so seeding from them there would
        # make `n` a copy of the profile being used rather than the fresh draft
        # it is meant to be.
        editor.hidden =
          if profile
            profile.hidden.dup
          elsif @model.scene_profiles.active_profile
            Set(String).new
          else
            @model.all_scenes.select(&.hidden).map(&.name).to_set
          end
        editor.cursor = 0
        editor.naming = false
        editor.name_input = ""
        editor.active = true
        true
      end

      # A click names its own row the way `PickScene` does, so a toggle cannot
      # land on the wrong scene if the list moved between the click being
      # reported and the action running.
      private def toggle_scene_profile_scene(index : Int32?) : ActionOutcome
        editor = @model.scene_profile_editor
        editor.cursor = index if index
        scene = @model.all_scenes[index || editor.cursor]?
        return ActionOutcome::HANDLED unless scene

        if editor.hidden.includes?(scene.name)
          editor.hidden.delete(scene.name)
        else
          editor.hidden.add(scene.name)
        end
        ActionOutcome::HANDLED
      end

      # Tab walks the saved profiles into the editor. Loading one replaces the
      # draft, unsaved toggles included -- the status line names what is now
      # being edited so that is visible rather than silent.
      private def cycle_scene_profile(offset : Int32) : ActionOutcome
        profiles = @model.scene_profiles.profiles
        return ActionOutcome.new(message: "no saved scene profiles") if profiles.empty?

        editor = @model.scene_profile_editor
        current = editor.name.empty? ? nil : @model.scene_profiles.index_of(editor.name)
        index = current ? (current + offset) % profiles.size : (offset > 0 ? 0 : profiles.size - 1)
        profile = profiles[index]
        editor.name = profile.name
        editor.hidden = profile.hidden.dup
        # Cycling onto a profile makes it the one the draft came from, so a
        # rename after a Tab renames the profile on screen rather than adding a
        # second one beside it.
        editor.origin_name = profile.name
        ActionOutcome.new(message: "editing scene profile: #{profile.name}")
      end

      # Saving hands the whole draft to the daemon in one command.
      #
      # One command rather than a save followed by a delete when the name
      # changed: `rename_from` moves the entry where it stands, which keeps it
      # in the position the user was looking at and keeps its hold on the
      # active profile. The two-command form rewrote the config file twice and
      # silently stopped hiding scenes whenever the profile being renamed was
      # the one in effect.
      #
      # Unlike the old client-side save this does *not* activate the profile.
      # The editor lets a user work on a profile they are not currently using,
      # and switching the scene list out from under them would be a surprise;
      # `<leader>p` is how a profile is put into effect.
      private def save_scene_profile(name : String) : ActionOutcome
        editor = @model.scene_profile_editor
        # The saved profile this save moves away from, and nil when nothing is
        # being moved: a draft saved under its own name is an edit of it, and a
        # draft whose origin is no longer in the list has nothing to rename.
        renamed_from = renamed_scene_profile(editor.origin_name, name)
        editor.active = false
        editor.naming = false
        editor.origin_name = name
        command(IPC::CommandPayload.new(
          name: IPC::CommandName::SAVE_SCENE_PROFILE,
          hidden: editor.hidden.to_a.sort!,
          rename_from: renamed_from,
          target: name
        ))
      end

      private def renamed_scene_profile(origin : String?, name : String) : String?
        return unless origin && origin != name
        @model.scene_profiles.index_of(origin) ? origin : nil
      end

      # The editor's naming sub-mode, which is a one-line text field with the
      # same key set as the command palette's.
      private def scene_profile_name_action(action : Action) : ActionOutcome?
        editor = @model.scene_profile_editor
        case action.kind
        when .scene_profiles_name_character?
          editor.name_input += action.character.to_s
          ActionOutcome::HANDLED
        when .scene_profiles_name_backspace?
          editor.name_input = drop_last_grapheme(editor.name_input)
          ActionOutcome::HANDLED
        when .scene_profiles_name_clear_line?
          editor.name_input = ""
          ActionOutcome::HANDLED
        when .scene_profiles_name_cancel?
          # Back to the list, not out of the editor: the draft is still there
          # to save under another name.
          editor.naming = false
          editor.name_input = ""
          ActionOutcome::HANDLED
        when .scene_profiles_name_submit?
          name = editor.name_input.strip
          return ActionOutcome.new(message: "scene profile name cannot be empty") if name.empty?

          # Refused rather than silently replacing the other profile: `upsert`
          # overwrites by name, and the only evidence would have been someone
          # else's hidden set quietly becoming this draft's. Saving over the
          # profile this draft came from is still allowed -- that is editing it.
          if @model.scene_profiles.index_of(name) && name != editor.origin_name
            return ActionOutcome.new(message: "a scene profile named '#{name}' already exists; open it from <leader>p to edit it")
          end

          # Naming is not saving. Confirming the name puts the draft back in
          # the list so more scenes can be toggled under it, and `Enter` there
          # is what writes the config -- which is what the box says on screen
          # ("n name" and "enter save" are separate hints, and the naming hint
          # reads "enter confirm").
          #
          # Saving here instead would also close the modal, so the `Enter` the
          # hint asks for next would land on the dashboard and switch the live
          # OBS scene under the cursor.
          editor.name = name
          editor.name_input = ""
          editor.naming = false
          ActionOutcome.new(message: "scene profile named: #{name}; press enter to save")
        end
      end

      private def palette_action(action : Action) : ActionOutcome?
        case action.kind
        when .open_palette?
          palette = @model.command_palette
          palette.active = true
          palette.input = (action.character || @model.command_palette_prefix[0]? || '/').to_s
          refresh_completions
          ActionOutcome::HANDLED
        when .close_palette?
          close_palette
          ActionOutcome::HANDLED
        when .palette_character?
          @model.command_palette.input += action.character.to_s
          refresh_completions
          ActionOutcome::HANDLED
        when .palette_backspace?
          @model.command_palette.input = drop_last_grapheme(@model.command_palette.input)
          refresh_completions
          ActionOutcome::HANDLED
        when .palette_submit?
          input = @model.command_palette.input
          close_palette
          dispatch_palette(input)
        when .palette_clear_line?
          # `Ctrl-U` clears the arguments but keeps the leader, so the line is
          # ready to retype rather than closed.
          palette = @model.command_palette
          palette.input = palette.input.each_grapheme.first(1).join
          refresh_completions
          ActionOutcome::HANDLED
        when .palette_delete_word?
          palette = @model.command_palette
          palette.input = palette.input.rstrip.sub(/[^\s]*$/, "")
          refresh_completions
          ActionOutcome::HANDLED
        when .complete_next?
          @model.command_palette.cycle_next
          ActionOutcome::HANDLED
        when .complete_previous?
          @model.command_palette.cycle_previous
          ActionOutcome::HANDLED
        when .pointer_completion?
          index = action.index
          completion = index ? @model.command_palette.completions[index]? : nil
          if completion
            @model.command_palette.input = completion
            @model.command_palette.completion_index = index
          end
          ActionOutcome::HANDLED
        end
      end

      private def navigation_action(action : Action) : ActionOutcome?
        case action.kind
        when .navigate_up?
          @model.move_up
          ActionOutcome::HANDLED
        when .navigate_down?
          @model.move_down
          ActionOutcome::HANDLED
        when .navigate_top?
          @model.move_top
          ActionOutcome::HANDLED
        when .navigate_bottom?
          @model.move_bottom
          ActionOutcome::HANDLED
        when .navigate_half_page_up?
          @model.move_by(-page_step)
          ActionOutcome::HANDLED
        when .navigate_half_page_down?
          @model.move_by(page_step)
          ActionOutcome::HANDLED
        when .volume_down? then volume(-5)
        when .volume_up?   then volume(5)
        end
      end

      # Half of the focused panel's visible rows, the way vim measures
      # `Ctrl-D`. Without a viewport -- before the first frame, or in a spec
      # that renders nothing -- a fixed step keeps the key useful.
      private def page_step : Int32
        area = @viewport.try(&.call)
        return DEFAULT_PAGE_STEP if area.nil? || area.empty?

        rows = DashboardLayout.compute(area, @model.streaming?).panel(@model.focus).height - 2
        {rows // 2, 1}.max
      end

      private def settings_action(action : Action) : ActionOutcome?
        case action.kind
        when .open_settings?
          @model.theme_preview_origin = @model.theme
          @model.settings_cursor = Theme::ALL.index(@model.theme) || 0
          @model.view = View::Settings
          ActionOutcome::HANDLED
        when .close_settings?
          @model.theme = @model.theme_preview_origin || @model.theme
          @model.theme_preview_origin = nil
          @model.view = View::Main
          ActionOutcome::HANDLED
        when .settings_navigate_up?
          @model.settings_cursor = {@model.settings_cursor - 1, 0}.max
          @model.theme = Theme::ALL[@model.settings_cursor]
          ActionOutcome::HANDLED
        when .settings_navigate_down?
          @model.settings_cursor = {@model.settings_cursor + 1, Theme::ALL.size - 1}.min
          @model.theme = Theme::ALL[@model.settings_cursor]
          ActionOutcome::HANDLED
        when .pointer_settings_select?
          index = action.index
          if index && (theme = Theme::ALL[index]?)
            @model.settings_cursor = index
            @model.theme = theme
          end
          ActionOutcome::HANDLED
        when .apply_settings_theme?, .pointer_settings_apply?
          @model.theme_preview_origin = nil
          @model.view = View::Main
          ActionOutcome.new(message: @theme_persister.try(&.call(@model.theme)) || "theme set: #{@model.theme.id}")
        end
      end

      POINTER_KINDS = [
        ActionKind::PointerFocus,
        ActionKind::PointerActivate,
        ActionKind::PointerToggleMute,
        ActionKind::PointerVolumeUp,
        ActionKind::PointerVolumeDown,
      ]

      # Pointer actions carry the panel and row they were resolved against, so
      # they place focus and the cursor themselves before doing anything. The
      # keyboard equivalents read whatever is focused; these must not, or a
      # click would act on the panel the keyboard happened to leave selected.
      private def pointer_action(action : Action) : ActionOutcome?
        panel = action.panel
        return unless panel
        return unless POINTER_KINDS.includes?(action.kind)

        @model.focus = panel
        if index = action.index
          @model.set_cursor(panel, index)
          @model.clamp_cursors
        end

        case action.kind
        when .pointer_activate?
          case panel
          when .scenes?      then command_action(Action.new(ActionKind::ActivateScene))
          when .profiles?    then command_action(Action.new(ActionKind::ActivateProfile))
          when .collections? then command_action(Action.new(ActionKind::ActivateCollection))
          when .audio?       then command_action(Action.new(ActionKind::ToggleMute))
          else                    ActionOutcome::HANDLED
          end
        when .pointer_toggle_mute?
          command_action(Action.new(ActionKind::ToggleMute))
        when .pointer_volume_up?
          # Through the ordinary volume path, so a spun wheel gets the same
          # optimistic redraw and debounced OBS command a held arrow key does.
          navigation_action(Action.new(ActionKind::VolumeUp))
        when .pointer_volume_down?
          navigation_action(Action.new(ActionKind::VolumeDown))
        else
          ActionOutcome::HANDLED
        end
      end

      private def command_action(action : Action) : ActionOutcome?
        case action.kind
        when .quit?           then ActionOutcome.new(quit: true)
        when .reload_config?  then command(IPC::CommandPayload.new(IPC::CommandName::RELOAD_CONFIG))
        when .dump_config?    then command(IPC::CommandPayload.new(IPC::CommandName::DUMP_CONFIG))
        when .retry_connect?  then ActionOutcome.new(retry_subscription: true, message: "Reconnected to daemon.")
        when .activate_scene? then target_command(IPC::CommandName::SET_SCENE, @model.focused_scene.try(&.name))
        when .activate_profile?
          target_command(IPC::CommandName::SET_PROFILE, @model.profiles[@model.profile_cursor]?)
        when .activate_collection?
          target_command(IPC::CommandName::SET_SCENE_COLLECTION, @model.scene_collections[@model.collection_cursor]?)
        when .toggle_mute?
          target_command(IPC::CommandName::TOGGLE_MUTE, @model.focused_audio.try(&.name))
        end
      end

      # The palette accepts either leader, so the line is read without one and
      # the vim spellings of quit and help are answered before the registry is
      # consulted.
      PALETTE_LEADERS = "/:"
      QUIT_WORDS      = ["q", "q!", "qa", "qa!", "quit", "quit!", "exit", "x", "wq"]
      HELP_WORDS      = ["h", "help"]

      private def dispatch_palette(input : String) : ActionOutcome
        line = input.strip.lstrip(PALETTE_LEADERS)
        normalized = line.strip.downcase
        return ActionOutcome.new(quit: true) if QUIT_WORDS.includes?(normalized)
        if SETTINGS_ALIASES.includes?(normalized)
          return handle(Action.new(ActionKind::OpenSettings))
        end
        if HELP_WORDS.includes?(normalized)
          return ActionOutcome.new(message: palette_help)
        end
        parsed = Domain::CommandParser.new.parse(line)
        command(payload_for(parsed))
      rescue ex : Domain::ObsctlError
        ActionOutcome.new(message: "error: #{ex.message}")
      end

      # `themes` is a dashboard-only view, so it has no registry entry and is
      # appended to the generated list.
      SETTINGS_ALIASES = ["themes", "theme", "settings"]

      private def palette_help : String
        usages = Domain::CommandRegistry
          .for_surface(Domain::CommandSurface::Palette)
          .map { |spec| "/#{spec.usage}" }
        "Commands: #{(usages << "/#{SETTINGS_ALIASES.first}").join(' ')}"
      end

      # Where the dashboard deliberately asks for something other than the
      # command's default IPC name.
      #
      # `/status` in the palette should refresh the panels rather than print a
      # report, and `/connect` is a request to re-establish the OBS link.
      TUI_PAYLOAD_OVERRIDES = {
        Domain::StatusCommand  => IPC::CommandName::GET_SNAPSHOT,
        Domain::ConnectCommand => IPC::CommandName::RECONNECT_OBS,
      }

      private def payload_for(command : Domain::Command) : IPC::CommandPayload
        {% for type, name in TUI_PAYLOAD_OVERRIDES %}
          return IPC::CommandPayload.new({{ name }}) if command.is_a?({{ type }})
        {% end %}

        command.to_payload
      end

      private def command(payload : IPC::CommandPayload) : ActionOutcome
        ActionOutcome.new(message: result_message(@sender.call(payload)))
      rescue ex : Domain::ObsctlError | IO::Error
        ActionOutcome.new(message: "error: #{ex.message}")
      end

      # The one line the status bar shows for a daemon response.
      #
      # Both the immediate command path and the debounced volume path report
      # what came back, and they have to word it identically — the user cannot
      # tell which of the two sent the request that produced the line.
      private def result_message(response : IPC::Response) : String
        return response.result.try(&.["message"]?).try(&.as_s?) || "ok" if response.ok

        error = response.error
        return "error: invalid server response" unless error

        "error [#{error.code}]: #{error.message}"
      end

      private def target_command(name : String, target : String?) : ActionOutcome
        return ActionOutcome::HANDLED unless target
        command(IPC::CommandPayload.new(name: name, target: target))
      end

      private def volume(delta : Int32) : ActionOutcome
        input = @model.focused_audio
        return ActionOutcome::HANDLED unless input
        percent = ((input.volume_percent || 50) + delta).clamp(0, 100)
        @model.preview_audio_volume(input.name, percent)
        debounce_volume(input.name, percent)
        ActionOutcome::HANDLED
      end

      private def debounce_volume(input_name : String, percent : Int32) : Nil
        version = @volume_versions[input_name] &+ 1
        @volume_versions[input_name] = version
        spawn(name: "obsctl-volume-debounce") do
          sleep @volume_debounce
          next unless @volume_versions[input_name] == version

          begin
            response = @sender.call(IPC::CommandPayload.new(name: IPC::CommandName::SET_VOLUME, target: input_name, percent: percent))
            # Only failures are announced: the level the user just set is
            # already on screen, so "ok" would say nothing they cannot see.
            @model.set_last_result(result_message(response)) unless response.ok
          rescue ex : Domain::ObsctlError | IO::Error
            @model.set_last_result("error: #{ex.message}")
          ensure
            # The edit is no longer in flight however it ended, so daemon
            # snapshots take over again. Only the fiber that survived the
            # version check gets here, so it is always the newest edit that
            # is being settled.
            @model.settle_volume(input_name)
          end
        end
      end

      # Bracketed paste is not a keystroke, so `Input` has no `Action` to map it
      # to and it arrives here directly rather than through `handle`. It still
      # has to land in whichever text field is open the way typing does —
      # appending to the line and recomputing completions — which is why the
      # append lives next to the `palette_character?` branch instead of being
      # spelled out again by the caller. Control characters are stripped: a
      # pasted newline would submit a command the user never chose to run.
      def paste(text : String) : Nil
        editor = @model.scene_profile_editor
        if editor.active && editor.naming
          # The same strip for the same reason as the palette below: a pasted
          # carriage return -- what a copied line ending arrives as -- would
          # otherwise submit, here saving a profile under a name the user never
          # chose.
          editor.name_input += text.gsub(/[\x00-\x08\x0B-\x1F\x7F]/, "")
          return
        end

        palette = @model.command_palette
        return unless palette.active

        palette.input += text.gsub(/[\x00-\x08\x0B-\x1F\x7F]/, "")
        refresh_completions
      end

      # Per grapheme, not per byte or per codepoint: one press has to
      # remove one character the user can see, including an emoji built out
      # of several codepoints.
      private def drop_last_grapheme(text : String) : String
        return text if text.empty?

        text.each_grapheme.to_a[0...-1].join
      end

      private def refresh_completions
        palette = @model.command_palette
        palette.completions = Completion.compute(palette.input, @model)
        palette.completion_index = nil
      end

      private def close_palette
        palette = @model.command_palette
        palette.active = false
        palette.input = ""
        palette.completions.clear
        palette.completion_index = nil
      end
    end
  end
end
