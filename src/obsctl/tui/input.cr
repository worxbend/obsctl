require "crytui"
require "./action"
require "./hit_test"
require "./keymap"
require "./model"
require "./scene_picker"
require "./scene_profile_list"

module Obsctl
  module TUI
    module Input
      extend self

      # Plain characters that map straight to an action.
      #
      # Checked before the control-modified bindings below, matching the
      # original ordering: `r` reloads whether or not control is held, while
      # `c` reaches FocusCollections only because control+c is claimed by Quit
      # earlier in `global_key`.
      SIMPLE_KEYS = {
        'r' => ActionKind::ReloadConfig,
        'D' => ActionKind::DumpConfig,
        'R' => ActionKind::RetryConnect,
        's' => ActionKind::FocusScenes,
        'a' => ActionKind::FocusAudio,
        'p' => ActionKind::FocusProfiles,
        'c' => ActionKind::FocusCollections,
      }

      # Resolves a key press to an action, or nil when nothing is bound.
      #
      # The scene-profile editor, the scene-profile list, the scene picker, the
      # palette and the settings views capture every key, so they
      # short-circuit. A half-typed key sequence captures every key too -- that
      # is what makes `<leader>` and `g` behave like prefixes rather than like
      # a keystroke that also does something on its own. Otherwise the binding
      # groups are tried in priority order; each returns nil to pass the key
      # along.
      #
      # The editor is tried before the list because opening the editor from the
      # list closes the list, so a frame where both are flagged active would be
      # a bug rather than a state to resolve.
      def handle_key(model : Model, key : CryTUI::KeyEvent) : Action?
        return scene_profiles_key(model, key) if model.scene_profile_editor.active
        return scene_profile_list_key(model, key) if model.scene_profile_list.active
        return scene_picker_key(model, key) if model.scene_picker_active
        return palette_key(key) if model.command_palette.active
        return settings_key(key) if model.view.settings?
        return sequence_key(model.pending_sequence, key) unless model.pending_sequence.empty?

        sequence_start(key) ||
          global_key(model, key) ||
          pane_focus_key(key) ||
          audio_key(model, key) ||
          navigation_key(key) ||
          activation_key(model, key)
      end

      # Resolves a mouse report to an action, or nil when the pointer is not
      # over anything actionable.
      #
      # Clicking a row focuses and selects it; clicking a row that is already
      # selected activates it. That deliberate second click is why a stray
      # click cannot cut the programme scene mid-broadcast, and it needs no
      # double-click timer to do it.
      def handle_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        return scene_profiles_mouse(model, event, area) if model.scene_profile_editor.active
        return scene_profile_list_mouse(model, event, area) if model.scene_profile_list.active
        return scene_picker_mouse(model, event, area) if model.scene_picker_active
        return which_key_mouse(model, event, area) unless model.pending_sequence.empty?
        return settings_mouse(model, event, area) if model.view.settings?
        return palette_mouse(model, event, area) if model.command_palette.active

        dashboard_mouse(model, event, area)
      end

      private def dashboard_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        return unless target = HitTest.resolve(model, area, event.column, event.row)

        if event.scroll?
          up = event.kind.scroll_up?

          # Over the audio matrix the wheel is a gain control, because that is
          # what a wheel does on a mixer. Holding shift falls back to moving
          # through the list, so inputs scrolled out of view are still
          # reachable without touching the keyboard.
          if target.panel.audio? && !event.modifiers.shift?
            index = target.index
            return Action.new(ActionKind::PointerFocus, panel: target.panel) unless index
            kind = up ? ActionKind::PointerVolumeUp : ActionKind::PointerVolumeDown
            return Action.new(kind, panel: target.panel, index: index)
          end

          kind = up ? ActionKind::NavigateUp : ActionKind::NavigateDown
          # Scrolling over a panel moves within it, so point at it first.
          return Action.new(kind, panel: target.panel, index: nil) if target.panel == model.focus
          return Action.new(ActionKind::PointerFocus, panel: target.panel, index: nil)
        end

        return unless left_press?(event)
        index = target.index
        return Action.new(ActionKind::PointerFocus, panel: target.panel) unless index

        if target.on_mute_control
          return Action.new(ActionKind::PointerToggleMute, panel: target.panel, index: index)
        end

        already_selected = target.panel == model.focus && index == model.cursor(target.panel)
        kind = already_selected ? ActionKind::PointerActivate : ActionKind::PointerFocus
        Action.new(kind, panel: target.panel, index: index)
      end

      # The which-key menu is clickable as well as typable: a click on a row
      # runs its binding or opens its group, and a click anywhere else means
      # the same thing Esc does.
      private def which_key_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        return unless left_press?(event)
        entry = HitTest.which_key_entry(model, area, event.column, event.row)
        return action(ActionKind::ClearSequence) unless entry

        resolve_sequence(entry.sequence)
      end

      # While the scene picker is open every key belongs to it: a label switches
      # straight to its scene, the arrows walk the list for scenes that ran out
      # of labels, Enter takes the one under the cursor, and Esc leaves.
      #
      # Nothing falls through to the dashboard, which is the point -- `q`, `a`
      # and `m` are all labels here, and a picker that let them quit or move
      # focus instead would be unusable. An unlabelled key does nothing rather
      # than closing, so a mistyped key costs a keystroke and not the picker.
      private def scene_picker_key(model : Model, key : CryTUI::KeyEvent) : Action?
        character = key.character
        control = key.modifiers.control?

        return action(ActionKind::CloseScenePicker) if cancel_key?(key)
        return action(ActionKind::ScenePickerActivate) if key.code.enter?
        return action(ActionKind::ScenePickerNavigateUp) if key.code.up?
        return action(ActionKind::ScenePickerNavigateDown) if key.code.down?
        # Control-modified keys are not labels; the only one the picker answers
        # to is the `Ctrl-C` handled above.
        return if control
        return unless character && key.code.character?

        index = ScenePicker.index_for(model.scene_picker_entries, character)
        index ? Action.new(ActionKind::PickScene, index: index) : nil
      end

      # The picker is clickable as well as typable, following the same rules the
      # which-key menu does: a click on a row runs it, a click anywhere else
      # means the same thing Esc does. The wheel moves the cursor.
      private def scene_picker_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        if action = scroll_action(event, ActionKind::ScenePickerNavigateUp, ActionKind::ScenePickerNavigateDown)
          return action
        end

        return unless left_press?(event)
        index = HitTest.scene_picker_index(model, area, event.column, event.row)
        index ? Action.new(ActionKind::PickScene, index: index) : action(ActionKind::CloseScenePicker)
      end

      # While the scene-profile editor is open every key belongs to it, the way
      # the scene picker claims every key: in here `q` does not quit and `t` is
      # not one of the dashboard's bindings. An unbound key does nothing rather
      # than closing, so a mistyped key costs a keystroke and not the draft.
      private def scene_profiles_key(model : Model, key : CryTUI::KeyEvent) : Action?
        return scene_profiles_name_key(key) if model.scene_profile_editor.naming

        character = key.character
        control = key.modifiers.control?

        return action(ActionKind::CloseSceneProfiles) if cancel_key?(key)
        return action(ActionKind::SceneProfilesSave) if key.code.enter?
        return action(ActionKind::SceneProfilesNavigateUp) if key.code.up?
        return action(ActionKind::SceneProfilesNavigateDown) if key.code.down?
        return action(ActionKind::SceneProfilesCycleNext) if key.code.tab?
        return action(ActionKind::SceneProfilesCyclePrevious) if key.code.back_tab?
        # Control-modified keys are not editor bindings; the only one it
        # answers to is the `Ctrl-C` handled above.
        return if control

        case character
        when 't', ' ' then action(ActionKind::SceneProfilesToggleScene)
        when 'j'      then action(ActionKind::SceneProfilesNavigateDown)
        when 'k'      then action(ActionKind::SceneProfilesNavigateUp)
        when 'n'      then action(ActionKind::SceneProfilesBeginNaming)
        when 'q'      then action(ActionKind::CloseSceneProfiles)
        end
      end

      # Naming a profile borrows four of the palette line's editing keys, so
      # that much muscle memory carries over: Esc or Ctrl-C to back out, Enter
      # to submit, Backspace, and Ctrl-U to clear the line. It stops there --
      # the palette's completion keys have nothing to complete in a name the
      # reader is inventing, and its Ctrl-W (delete the last word) is not bound
      # here.
      #
      # Esc backs out to the list rather than closing the editor: the draft is
      # still there to save under another name.
      private def scene_profiles_name_key(key : CryTUI::KeyEvent) : Action?
        character = key.character
        control = key.modifiers.control?

        return action(ActionKind::SceneProfilesNameCancel) if cancel_key?(key)
        return action(ActionKind::SceneProfilesNameSubmit) if key.code.enter?
        return action(ActionKind::SceneProfilesNameBackspace) if key.code.backspace?
        return action(ActionKind::SceneProfilesNameClearLine) if character == 'u' && control

        character_action(key, ActionKind::SceneProfilesNameCharacter)
      end

      # Clickable on the same rules the picker follows: a click on a row
      # toggles it, a click anywhere else means what Esc means, and the wheel
      # moves the cursor.
      private def scene_profiles_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        # While a name is being typed the modal is a text field, not a list:
        # the pointer would otherwise change the draft underneath the reader,
        # with the field still on screen saying nothing about it.
        return if model.scene_profile_editor.naming

        if action = scroll_action(event, ActionKind::SceneProfilesNavigateUp, ActionKind::SceneProfilesNavigateDown)
          return action
        end

        return unless left_press?(event)
        index = HitTest.scene_profiles_index(model, area, event.column, event.row)
        index ? Action.new(ActionKind::SceneProfilesToggleScene, index: index) : action(ActionKind::CloseSceneProfiles)
      end

      # While the scene-profile list is open every key belongs to it, the way the
      # scene picker claims every key. A digit puts that row into effect at
      # once; the letters are verbs on the row under the cursor. An unbound key
      # does nothing rather than closing, so a mistyped key costs a keystroke
      # and not the modal.
      private def scene_profile_list_key(model : Model, key : CryTUI::KeyEvent) : Action?
        return scene_profile_list_confirm_key(key) if model.scene_profile_list.confirming

        character = key.character
        control = key.modifiers.control?

        return action(ActionKind::CloseSceneProfileList) if cancel_key?(key)
        return action(ActionKind::SceneProfileListActivate) if key.code.enter?
        return action(ActionKind::SceneProfileListNavigateUp) if key.code.up?
        return action(ActionKind::SceneProfileListNavigateDown) if key.code.down?
        # Control-modified keys are neither labels nor verbs; the only one the
        # list answers to is the `Ctrl-C` handled above.
        return if control

        case character
        when 'j' then action(ActionKind::SceneProfileListNavigateDown)
        when 'k' then action(ActionKind::SceneProfileListNavigateUp)
        when 'e' then action(ActionKind::SceneProfileListEdit)
        when 'r' then action(ActionKind::SceneProfileListRename)
        when 'n' then action(ActionKind::SceneProfileListNew)
        when 'd' then action(ActionKind::SceneProfileListDeletePrompt)
        when 'q' then action(ActionKind::CloseSceneProfileList)
        else          scene_profile_list_label(model, key)
        end
      end

      # A digit press, which names its own row rather than moving the cursor
      # onto it first. Lifted out of the `case` above so neither method carries
      # more branches than ameba's complexity ratchet allows.
      private def scene_profile_list_label(model : Model, key : CryTUI::KeyEvent) : Action?
        character = key.character
        return unless character && key.code.character?

        index = SceneProfileList.index_for(model.scene_profile_list_entries, character)
        index ? Action.new(ActionKind::PickSceneProfile, index: index) : nil
      end

      # A delete waiting for its second press. Everything that is not the
      # confirmation cancels it: there is no undo for a deleted profile, so the
      # only key that removes one is the one the on-screen hint asks for.
      private def scene_profile_list_confirm_key(key : CryTUI::KeyEvent) : Action?
        # `d` and nothing else. Enter is the list's "use this row" key while
        # browsing, so accepting it here would let a user who armed a delete by
        # mistake destroy the profile with the key that normally means "yes,
        # this one" -- and the hint row and docs both promise only `d`.
        return action(ActionKind::SceneProfileListDeleteConfirm) if key.character == 'd' && !key.modifiers.control?

        action(ActionKind::SceneProfileListDeleteCancel)
      end

      # Clickable on the same rules the picker follows: a click on a row puts it
      # into effect, a click anywhere else means what Esc means, and the wheel
      # moves the cursor. An armed delete swallows the press and disarms, so a
      # stray click can never be the second press that removes a profile --
      # while the wheel still scrolls, because browsing is not answering the
      # question.
      private def scene_profile_list_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        if action = scroll_action(event, ActionKind::SceneProfileListNavigateUp, ActionKind::SceneProfileListNavigateDown)
          return action
        end

        return unless left_press?(event)
        # Only an actual button press disarms. A single click reports press and
        # release, and a mouse that moved reports a drag, so cancelling on any
        # event at all would say "delete cancelled" twice for one click.
        return action(ActionKind::SceneProfileListDeleteCancel) if model.scene_profile_list.confirming

        index = HitTest.scene_profile_list_index(model, area, event.column, event.row)
        index ? Action.new(ActionKind::PickSceneProfile, index: index) : action(ActionKind::CloseSceneProfileList)
      end

      # Clicking a theme previews it and clicking the previewed theme applies
      # it, the same click-then-confirm rule the dashboard rows follow.
      private def settings_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        if action = scroll_action(event, ActionKind::SettingsNavigateUp, ActionKind::SettingsNavigateDown)
          return action
        end

        return unless left_press?(event)
        return unless index = HitTest.settings_index(model, area, event.column, event.row)

        return action(ActionKind::PointerSettingsApply) if index == model.settings_cursor
        Action.new(ActionKind::PointerSettingsSelect, index: index)
      end

      # While the palette is open the wheel walks the completions and a click
      # picks the chip under the pointer. A click outside the panel closes the
      # palette, which is what clicking away from a prompt normally means.
      private def palette_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        if action = scroll_action(event, ActionKind::CompletePrevious, ActionKind::CompleteNext)
          return action
        end

        return unless left_press?(event)
        if index = HitTest.palette_completion(model, area, event.column, event.row)
          return Action.new(ActionKind::PointerCompletion, index: index)
        end

        palette = HitTest.palette_area(model, area)
        inside = event.column >= palette.x && event.column < palette.right &&
                 event.row >= palette.y && event.row < palette.bottom
        inside ? nil : action(ActionKind::ClosePalette)
      end

      # A key pressed with nothing pending: it either is a sequence binding on
      # its own, opens one, or belongs to some other group of bindings.
      private def sequence_start(key : CryTUI::KeyEvent) : Action?
        return unless token = Keymap.token(key)

        resolve_sequence(token)
      end

      # A key pressed while a sequence is half typed. Anything that neither
      # completes nor extends it cancels, so a mistyped prefix never leaves the
      # dashboard waiting.
      private def sequence_key(pending : String, key : CryTUI::KeyEvent) : Action
        return action(ActionKind::ClearSequence) unless token = Keymap.token(key)

        resolve_sequence(pending + token) || action(ActionKind::ClearSequence)
      end

      private def resolve_sequence(sequence : String) : Action?
        if kind = Keymap[sequence]
          return action(kind)
        end
        return Action.new(ActionKind::PendingSequence, sequence: sequence) if Keymap.prefix?(sequence)
        nil
      end

      private def global_key(model : Model, key : CryTUI::KeyEvent) : Action?
        character = key.character
        control = key.modifiers.control?

        return action(ActionKind::OpenSettings) if function?(key, 2) || (character == 't' && control)
        return action(ActionKind::Quit) if character == 'q' || (character == 'c' && control)
        if character && !control && (character == ':' || model.command_palette_prefix.includes?(character))
          # The palette opens with the key that was pressed, so `:` gives a vim
          # command line and the configured prefix gives the obsctl one.
          return Action.new(ActionKind::OpenPalette, character)
        end

        return unless character
        SIMPLE_KEYS[character]?.try { |kind| action(kind) }
      end

      # Control plus an arrow or hjkl moves focus between panes.
      private def pane_focus_key(key : CryTUI::KeyEvent) : Action?
        return unless key.modifiers.control?

        character = key.character
        return action(ActionKind::FocusPaneLeft) if key.code.left? || character == 'h'
        return action(ActionKind::FocusPaneRight) if key.code.right? || character == 'l'
        return action(ActionKind::FocusPaneUp) if key.code.up? || character == 'k'
        return action(ActionKind::FocusPaneDown) if key.code.down? || character == 'j'
        nil
      end

      private def navigation_key(key : CryTUI::KeyEvent) : Action?
        character = key.character
        return action(ActionKind::NavigateUp) if key.code.up? || character == 'k'
        return action(ActionKind::NavigateDown) if key.code.down? || character == 'j'
        return action(ActionKind::NavigateTop) if key.code.home?
        return action(ActionKind::NavigateBottom) if key.code.end?
        return action(ActionKind::NavigateHalfPageUp) if key.code.page_up?
        return action(ActionKind::NavigateHalfPageDown) if key.code.page_down?
        nil
      end

      private def activation_key(model : Model, key : CryTUI::KeyEvent) : Action?
        return unless key.code.enter?

        return action(ActionKind::ActivateScene) if model.focus.scenes?
        return action(ActionKind::ActivateProfile) if model.focus.profiles?
        return action(ActionKind::ActivateCollection) if model.focus.collections?
        nil
      end

      # The audio matrix is a mixing desk laid out sideways, so its keys follow
      # its axes rather than the list conventions the other panels use: left
      # and right walk the channel strips, up and down ride the fader of the
      # one selected. Checked before `navigation_key` so the vertical keys
      # reach the fader, but after `pane_focus_key` so `Ctrl-h` still leaves
      # the panel.
      private def audio_key(model : Model, key : CryTUI::KeyEvent) : Action?
        return unless model.focus.audio?

        character = key.character
        return action(ActionKind::ToggleMute) if character == 'm'
        return action(ActionKind::NavigateUp) if key.code.left? || character == 'h'
        return action(ActionKind::NavigateDown) if key.code.right? || character == 'l'
        return action(ActionKind::VolumeUp) if key.code.up? || character == 'k'
        return action(ActionKind::VolumeDown) if key.code.down? || character == 'j'
        nil
      end

      # The palette line is edited with the readline keys vim's command line
      # uses, so muscle memory from `:` in Neovim carries over.
      private def palette_key(key : CryTUI::KeyEvent) : Action?
        character = key.character
        control = key.modifiers.control?

        return action(ActionKind::ClosePalette) if cancel_key?(key)
        return action(ActionKind::PaletteSubmit) if key.code.enter?
        return action(ActionKind::PaletteBackspace) if key.code.backspace?
        return action(ActionKind::PaletteClearLine) if character == 'u' && control
        return action(ActionKind::PaletteDeleteWord) if character == 'w' && control
        return action(ActionKind::CompleteNext) if key.code.tab? || (character == 'n' && control)
        return action(ActionKind::CompletePrevious) if key.code.back_tab? || (character == 'p' && control)

        character_action(key, ActionKind::PaletteCharacter)
      end

      # Esc, F2 and `q` close the appearance lab. Ctrl-C, which every modal
      # above takes as a second way out, is not one of them: `handle_key`
      # returns whatever this gives back, so while the lab is open Ctrl-C
      # neither closes it nor reaches the dashboard's Quit binding.
      private def settings_key(key : CryTUI::KeyEvent) : Action?
        character = key.character
        return action(ActionKind::CloseSettings) if key.code.escape? || function?(key, 2) || character == 'q'
        return action(ActionKind::SettingsNavigateUp) if key.code.up? || character == 'k'
        return action(ActionKind::SettingsNavigateDown) if key.code.down? || character == 'j'
        return action(ActionKind::ApplySettingsTheme) if key.code.enter?
        nil
      end

      private def function?(key : CryTUI::KeyEvent, number : Int32) : Bool
        key.code.function? && key.function == number
      end

      private def action(kind : ActionKind) : Action
        Action.new(kind)
      end

      private def cancel_key?(key : CryTUI::KeyEvent) : Bool
        key.code.escape? || (key.character == 'c' && key.modifiers.control?)
      end

      private def scroll_action(event : CryTUI::MouseEvent, up : ActionKind, down : ActionKind) : Action?
        return unless event.scroll?

        action(event.kind.scroll_up? ? up : down)
      end

      private def left_press?(event : CryTUI::MouseEvent) : Bool
        event.kind.press? && event.button.left?
      end

      private def character_action(key : CryTUI::KeyEvent, kind : ActionKind) : Action?
        character = key.character
        return if key.modifiers.control?
        return unless key.code.character? && character

        Action.new(kind, character)
      end
    end
  end
end
