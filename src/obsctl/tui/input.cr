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

      def handle_key(model : Model, key : CryTUI::KeyEvent) : Action?
        return palette_key(key) if model.command_palette.active
        return settings_key(key) if model.view.settings?

        character = key.character
        control = key.modifiers.control?

        return action(ActionKind::OpenSettings) if function?(key, 2) || (character == 't' && control)
        return action(ActionKind::Quit) if character == 'q' || (character == 'c' && control)
        return action(ActionKind::OpenPalette) if character == ':' || (character && model.command_palette_prefix.includes?(character))
        return action(ActionKind::ReloadConfig) if character == 'r'
        return action(ActionKind::DumpConfig) if character == 'D'
        return action(ActionKind::RetryConnect) if character == 'R'
        return action(ActionKind::FocusScenes) if character == 's'
        return action(ActionKind::FocusAudio) if character == 'a'
        return action(ActionKind::FocusProfiles) if character == 'p'
        return action(ActionKind::FocusCollections) if character == 'c'

        return action(ActionKind::FocusPaneLeft) if control && (key.code.left? || character == 'h')
        return action(ActionKind::FocusPaneRight) if control && (key.code.right? || character == 'l')
        return action(ActionKind::FocusPaneUp) if control && (key.code.up? || character == 'k')
        return action(ActionKind::FocusPaneDown) if control && (key.code.down? || character == 'j')
        return action(ActionKind::NavigateUp) if key.code.up? || character == 'k'
        return action(ActionKind::NavigateDown) if key.code.down? || character == 'j'

        if key.code.enter?
          return action(ActionKind::ActivateScene) if model.focus.scenes?
          return action(ActionKind::ActivateProfile) if model.focus.profiles?
          return action(ActionKind::ActivateCollection) if model.focus.collections?
        end

        if model.focus.audio?
          return action(ActionKind::ToggleMute) if character == 'm'
          return action(ActionKind::VolumeDown) if key.code.left? || character == 'h'
          return action(ActionKind::VolumeUp) if key.code.right? || character == 'l'
        end
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
