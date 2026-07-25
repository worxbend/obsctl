require "../../crytui"
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
    end

    struct Action
      getter kind : ActionKind
      getter character : Char?

      def initialize(@kind, @character = nil)
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
