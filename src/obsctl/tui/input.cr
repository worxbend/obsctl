require "../../crytui"
require "./hit_test"
require "./model"

module Obsctl
  module TUI
    enum ActionKind
      Quit
      OpenPalette
      ClosePalette
      PaletteCharacter
      PaletteBackspace
      PaletteSubmit
      ReloadConfig
      DumpConfig
      RetryConnect
      FocusScenes
      FocusAudio
      FocusProfiles
      FocusCollections
      FocusPaneLeft
      FocusPaneRight
      FocusPaneUp
      FocusPaneDown
      NavigateUp
      NavigateDown
      ActivateScene
      ActivateProfile
      ActivateCollection
      ToggleMute
      VolumeDown
      VolumeUp
      CompleteNext
      CompletePrevious
      OpenSettings
      CloseSettings
      SettingsNavigateUp
      SettingsNavigateDown
      ApplySettingsTheme
      PointerFocus
      PointerActivate
      PointerToggleMute
      PointerVolumeUp
      PointerVolumeDown
    end

    struct Action
      getter kind : ActionKind
      getter character : Char?
      # Pointer actions name their own target instead of acting on whatever is
      # focused, so a click cannot be applied to the wrong panel if focus moves
      # between the report arriving and the action running.
      getter panel : FocusPanel?
      getter index : Int32?

      def initialize(@kind, @character = nil, @panel = nil, @index = nil)
      end
    end

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
      # The palette and settings views capture every key, so they short-circuit.
      # Otherwise the binding groups are tried in priority order; each returns
      # nil to pass the key along.
      def handle_key(model : Model, key : CryTUI::KeyEvent) : Action?
        return palette_key(key) if model.command_palette.active
        return settings_key(key) if model.view.settings?

        global_key(model, key) ||
          pane_focus_key(key) ||
          navigation_key(key) ||
          activation_key(model, key) ||
          audio_key(model, key)
      end

      # Resolves a mouse report to an action, or nil when the pointer is not
      # over anything actionable.
      #
      # Clicking a row focuses and selects it; clicking a row that is already
      # selected activates it. That deliberate second click is why a stray
      # click cannot cut the programme scene mid-broadcast, and it needs no
      # double-click timer to do it.
      def handle_mouse(model : Model, event : CryTUI::MouseEvent, area : CryTUI::Rect) : Action?
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

      private def selected_index(model : Model, panel : FocusPanel) : Int32
        case panel
        when .scenes?      then model.scene_cursor
        when .audio?       then model.audio_cursor
        when .profiles?    then model.profile_cursor
        when .collections? then model.collection_cursor
        else                    -1
        end
      end

      private def global_key(model : Model, key : CryTUI::KeyEvent) : Action?
        character = key.character
        control = key.modifiers.control?

        return action(ActionKind::OpenSettings) if function?(key, 2) || (character == 't' && control)
        return action(ActionKind::Quit) if character == 'q' || (character == 'c' && control)
        return action(ActionKind::OpenPalette) if character == ':' || (character && model.command_palette_prefix.includes?(character))

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
        nil
      end

      private def activation_key(model : Model, key : CryTUI::KeyEvent) : Action?
        return unless key.code.enter?

        return action(ActionKind::ActivateScene) if model.focus.scenes?
        return action(ActionKind::ActivateProfile) if model.focus.profiles?
        return action(ActionKind::ActivateCollection) if model.focus.collections?
        nil
      end

      private def audio_key(model : Model, key : CryTUI::KeyEvent) : Action?
        return unless model.focus.audio?

        character = key.character
        return action(ActionKind::ToggleMute) if character == 'm'
        return action(ActionKind::VolumeDown) if key.code.left? || character == 'h'
        return action(ActionKind::VolumeUp) if key.code.right? || character == 'l'
        nil
      end

      private def palette_key(key : CryTUI::KeyEvent) : Action?
        character = key.character
        return action(ActionKind::ClosePalette) if key.code.escape? || (character == 'c' && key.modifiers.control?)
        return action(ActionKind::PaletteSubmit) if key.code.enter?
        return action(ActionKind::PaletteBackspace) if key.code.backspace?
        return action(ActionKind::CompleteNext) if key.code.tab?
        return action(ActionKind::CompletePrevious) if key.code.back_tab?
        return Action.new(ActionKind::PaletteCharacter, character) if key.code.character? && character
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
