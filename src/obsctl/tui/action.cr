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
      PaletteClearLine
      PaletteDeleteWord
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
      NavigateTop
      NavigateBottom
      NavigateHalfPageUp
      NavigateHalfPageDown
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
      OpenScenePicker
      CloseScenePicker
      ScenePickerNavigateUp
      ScenePickerNavigateDown
      ScenePickerActivate
      # Switch to the scene at `index`, from a label press or a click on the
      # picker. It names its own scene rather than acting on a cursor, so the
      # switch cannot land on the wrong one if the list moves underneath it.
      PickScene
      # A key that begins a multi-key sequence, e.g. `g` or the leader.
      PendingSequence
      ClearSequence
      PointerFocus
      PointerActivate
      PointerToggleMute
      PointerVolumeUp
      PointerVolumeDown
      PointerCompletion
      PointerSettingsSelect
      PointerSettingsApply
    end

    struct Action
      getter kind : ActionKind
      getter character : Char?
      # Pointer actions name their own target instead of acting on whatever is
      # focused, so a click cannot be applied to the wrong panel if focus moves
      # between the report arriving and the action running.
      getter panel : FocusPanel?
      getter index : Int32?
      # The key sequence a `PendingSequence` action is waiting to complete.
      getter sequence : String?

      def initialize(@kind, @character = nil, @panel = nil, @index = nil, @sequence = nil)
      end
    end
  end
end
