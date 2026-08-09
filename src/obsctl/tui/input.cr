require "../../crytui"
require "./action"
require "./hit_test"
require "./keymap"
require "./model"
require "./scene_picker"

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
      # The scene picker, the palette and the settings views capture every key,
      # so they short-circuit. A half-typed key sequence captures every key too
      # -- that is what makes `<leader>` and `g` behave like prefixes rather
      # than like a keystroke that also does something on its own. Otherwise
      # the binding groups are tried in priority order; each returns nil to
      # pass the key along.
      def handle_key(model : Model, key : CryTUI::KeyEvent) : Action?
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

        return unless event.kind.press? && event.button.left?
        index = target.index
        return Action.new(ActionKind::PointerFocus, panel: target.panel) unless index

        if target.on_mute_control
          return Action.new(ActionKind::PointerToggleMute, panel: target.panel, index: index)
        end

        already_selected = target.panel == model.focus && index == selected_index(model, target.panel)
        kind = already_selected ? ActionKind::PointerActivate : ActionKind::PointerFocus
        Action.new(kind, panel: target.panel, index: index)
      end

      # The which-key menu is clickable as well as typable: a click on a row
      # runs its binding or opens its group, and a click anywhere else means
      # the same thing Esc does.
      private def which_key_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        return unless event.kind.press? && event.button.left?
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

        return action(ActionKind::CloseScenePicker) if key.code.escape? || (character == 'c' && control)
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
        if event.scroll?
          return action(event.kind.scroll_up? ? ActionKind::ScenePickerNavigateUp : ActionKind::ScenePickerNavigateDown)
        end

        return unless event.kind.press? && event.button.left?
        index = HitTest.scene_picker_index(model, area, event.column, event.row)
        index ? Action.new(ActionKind::PickScene, index: index) : action(ActionKind::CloseScenePicker)
      end

      # Clicking a theme previews it and clicking the previewed theme applies
      # it, the same click-then-confirm rule the dashboard rows follow.
      private def settings_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        if event.scroll?
          return action(event.kind.scroll_up? ? ActionKind::SettingsNavigateUp : ActionKind::SettingsNavigateDown)
        end

        return unless event.kind.press? && event.button.left?
        return unless index = HitTest.settings_index(model, area, event.column, event.row)

        return action(ActionKind::PointerSettingsApply) if index == model.settings_cursor
        Action.new(ActionKind::PointerSettingsSelect, index: index)
      end

      # While the palette is open the wheel walks the completions and a click
      # picks the chip under the pointer. A click outside the panel closes the
      # palette, which is what clicking away from a prompt normally means.
      private def palette_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
        if event.scroll?
          return action(event.kind.scroll_up? ? ActionKind::CompletePrevious : ActionKind::CompleteNext)
        end

        return unless event.kind.press? && event.button.left?
        if index = HitTest.palette_completion(model, area, event.column, event.row)
          return Action.new(ActionKind::PointerCompletion, index: index)
        end

        palette = HitTest.palette_area(model, area)
        inside = event.column >= palette.x && event.column < palette.right &&
                 event.row >= palette.y && event.row < palette.bottom
        inside ? nil : action(ActionKind::ClosePalette)
      end

      private def selected_index(model : Model, panel : FocusPanel) : Int32
        case panel
        when .scenes?      then model.scene_cursor
        when .audio?       then model.audio_cursor
        when .profiles?    then model.profile_cursor
        when .collections? then model.collection_cursor
        else                    -1
        end
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

        return action(ActionKind::ClosePalette) if key.code.escape? || (character == 'c' && control)
        return action(ActionKind::PaletteSubmit) if key.code.enter?
        return action(ActionKind::PaletteBackspace) if key.code.backspace?
        return action(ActionKind::PaletteClearLine) if character == 'u' && control
        return action(ActionKind::PaletteDeleteWord) if character == 'w' && control
        return action(ActionKind::CompleteNext) if key.code.tab? || (character == 'n' && control)
        return action(ActionKind::CompletePrevious) if key.code.back_tab? || (character == 'p' && control)
        return Action.new(ActionKind::PaletteCharacter, character) if key.code.character? && character && !control
        nil
      end

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
    end
  end
end
