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
      # The scene-profile editor: obsctl's own named sets of scenes the
      # dashboard leaves out of its scene list. Unrelated to OBS profiles and
      # OBS scene collections, which have their own panels and their own
      # actions.
      OpenSceneProfiles
      CloseSceneProfiles
      SceneProfilesNavigateUp
      SceneProfilesNavigateDown
      # Hide or unhide one scene in the draft. `index` nil means the row under
      # the editor's cursor and a set `index` means the row that was clicked,
      # the same rule `PickScene` follows.
      SceneProfilesToggleScene
      SceneProfilesCycleNext
      SceneProfilesCyclePrevious
      SceneProfilesBeginNaming
      SceneProfilesSave
      SceneProfilesNameCharacter
      SceneProfilesNameBackspace
      SceneProfilesNameClearLine
      SceneProfilesNameSubmit
      SceneProfilesNameCancel
      # The scene-profile list: choosing which saved profile is in effect, and
      # managing the saved ones. Distinct from the editor above, which builds
      # the set of scenes one profile hides. Nothing here reaches OBS or the
      # daemon either -- it changes which scenes this dashboard draws.
      OpenSceneProfileList
      CloseSceneProfileList
      SceneProfileListNavigateUp
      SceneProfileListNavigateDown
      SceneProfileListActivate
      # Put the row at `index` into effect, from a digit press or a click. It
      # names its own row rather than acting on a cursor, the same rule
      # `PickScene` follows, so it cannot land on the wrong profile if the list
      # moved underneath it. Row 0 is "show every scene".
      PickSceneProfile
      SceneProfileListEdit
      SceneProfileListRename
      SceneProfileListNew
      SceneProfileListDeletePrompt
      SceneProfileListDeleteConfirm
      SceneProfileListDeleteCancel
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
