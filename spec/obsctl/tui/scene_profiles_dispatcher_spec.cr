require "../../spec_helper"
require "../../support/scene_profiles"
require "../../../src/obsctl/tui/dispatcher"

private ALL_SCENES = ["Main", "Cam", "Utility Cam", "BRB Loop"]

private def profile_model(names = ALL_SCENES, hidden = ["Utility Cam"])
  model = Obsctl::TUI::Model.new
  model.connected_to_daemon = true
  model.snapshot = Obsctl::OBS::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: names.first?,
    scenes: names.map_with_index do |name, index|
      Obsctl::OBS::State::SceneState.new(name, active: index == 0, hidden: hidden.includes?(name))
    end,
    audio_inputs: [] of Obsctl::OBS::State::AudioState
  )
  model
end

private def profile_dispatcher(model)
  sent = [] of Obsctl::IPC::CommandPayload
  sender = ->(payload : Obsctl::IPC::CommandPayload) do
    sent << payload
    Obsctl::IPC::Response.new("test", true, JSON.parse(%({"message":"ok"})))
  end
  {sent, Obsctl::TUI::Dispatcher.new(model, sender)}
end

private def act(dispatcher, kind : Obsctl::TUI::ActionKind, index : Int32? = nil, character : Char? = nil)
  dispatcher.handle(Obsctl::TUI::Action.new(kind, character: character, index: index))
end

private def profiles(*entries : Tuple(String, Array(String)))
  Obsctl::TUI::SceneProfiles.new(entries.to_a.map { |(name, hidden)| Obsctl::TUI::SceneProfile.new(name, hidden.to_set) })
end

describe "scene profile editor dispatch" do
  describe "opening" do
    it "seeds the draft from the scenes the config already hides" do
      # Adopting profiles must not move anything: the first draft is exactly
      # what the dashboard is drawing at the moment the editor opens.
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)

      editor = model.scene_profile_editor
      editor.active.should be_true
      editor.naming.should be_false
      editor.cursor.should eq(0)
      editor.name.should eq("")
      editor.hidden.should eq(["Utility Cam"].to_set)
      # Opening alone changes nothing the dashboard reads.
      model.scene_profiles.profiles.should be_empty
      model.scene_profiles.active.should be_nil
    end

    it "seeds the draft from the active profile when there is one" do
      model = profile_model
      set_scene_profiles(model, profiles({"streaming", ["BRB Loop"]}).activate("streaming"))
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)

      model.scene_profile_editor.name.should eq("streaming")
      model.scene_profile_editor.hidden.should eq(["BRB Loop"].to_set)
    end

    it "refuses to open with no scenes, because it would swallow keys for nothing" do
      model = profile_model([] of String, [] of String)
      _, dispatcher = profile_dispatcher(model)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)

      model.scene_profile_editor.active.should be_false
      outcome.message.should eq("no scenes to configure")
    end
  end

  describe "toggling" do
    it "toggles the cursor row both ways" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene)
      model.scene_profile_editor.hidden.should eq(["Utility Cam", "Main"].to_set)

      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene)
      model.scene_profile_editor.hidden.should eq(["Utility Cam"].to_set)
    end

    it "moves the cursor to the row a click named and toggles that one" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 3)

      model.scene_profile_editor.cursor.should eq(3)
      model.scene_profile_editor.hidden.should eq(["Utility Cam", "BRB Loop"].to_set)
    end

    it "ignores a row that is not there" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 99)

      model.scene_profile_editor.hidden.should eq(["Utility Cam"].to_set)
    end

    it "lists hidden scenes too, so a toggle can bring one back" do
      # Row 2 is `Utility Cam`, which the dashboard is not drawing. The editor
      # is the one surface that shows it, and `t` on it is the way back.
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 2)

      model.scene_profile_editor.hidden.should be_empty
    end

    it "clamps the cursor at both ends instead of wrapping" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      3.times { act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNavigateUp) }
      model.scene_profile_editor.cursor.should eq(0)
      9.times { act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNavigateDown) }
      model.scene_profile_editor.cursor.should eq(ALL_SCENES.size - 1)
    end

    it "does not change what the dashboard draws until the draft is saved" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 0)

      model.scenes.map(&.name).should eq(["Main", "Cam", "BRB Loop"])
      model.scene_profiles.profiles.should be_empty
    end
  end

  describe "cancelling" do
    it "leaves the visible scenes and the saved profiles exactly as they were" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 0)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::CloseSceneProfiles)

      model.scene_profile_editor.active.should be_false
      model.scenes.map(&.name).should eq(["Main", "Cam", "BRB Loop"])
      model.scene_profiles.profiles.should be_empty
      model.scene_profiles.active.should be_nil
      outcome.message.should eq("scene profile editing cancelled")
    end
  end

  describe "saving" do
    it "asks for a name rather than failing when the draft has none" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesSave)

      model.scene_profile_editor.active.should be_true
      model.scene_profile_editor.naming.should be_true
      model.scene_profiles.profiles.should be_empty
      outcome.message.should eq("name this scene profile")
    end

    it "refuses a name that is only whitespace" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "  ".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)

      outcome.message.should eq("scene profile name cannot be empty")
      model.scene_profile_editor.naming.should be_true
      model.scene_profiles.profiles.should be_empty
    end

    # Naming and saving are two steps, which is what the box says on screen:
    # the list hint offers "n name" and "enter save" separately, and the naming
    # hint reads "enter confirm". If confirming a name also saved, it would
    # close the modal, and the `Enter` the hint asks for next would reach the
    # dashboard and switch the live OBS scene.
    it "confirms a name without writing anything, leaving the modal open" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)

      model.scene_profile_editor.active.should be_true
      model.scene_profile_editor.naming.should be_false
      model.scene_profile_editor.name.should eq("solo")
      model.scene_profile_editor.name_input.should eq("")
      model.scene_profiles.profiles.should be_empty
      model.scene_profiles.active.should be_nil
      outcome.message.should eq("scene profile named: solo; press enter to save")
    end

    it "sends the edited draft and closes the modal" do
      model = profile_model
      sent, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      # Hide `Cam` on top of the `Utility Cam` the draft started with, and
      # bring `Utility Cam` back, so the saved set is neither the old one nor
      # the whole list.
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 1)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 2)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesSave)

      model.scene_profile_editor.active.should be_false
      model.scene_profile_editor.naming.should be_false
      sent.map(&.target).should eq(["solo"])
      sent.first.hidden.should eq(["Cam"])
      # Saving does not activate. The editor lets a user work on a profile they
      # are not using, and switching the scene list out from under them would
      # be a surprise; `<leader>p` is how a profile is put into effect.
      model.scene_profiles.active.should be_nil
    end

    it "saves under the existing name, which is what makes the daemon replace it" do
      model = profile_model
      set_scene_profiles(model, profiles({"streaming", ["BRB Loop"]}, {"editing", [] of String}).activate("streaming"))
      sent, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 1)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesSave)

      command = sent.first
      command.target.should eq("streaming")
      command.hidden.should eq(["BRB Loop", "Cam"])
      # Not a rename, so the key is absent: the daemon replaces the same-named
      # entry rather than moving one.
      command.rename_from.should be_nil
    end

    it "brings cursors back inside a scene list that just got shorter" do
      model = profile_model
      model.scene_cursor = 3
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      ALL_SCENES.each_index { |index| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: index) }
      # Only `Main` survives: the draft started holding `Utility Cam`, so
      # toggling every row hides the other three and unhides that one.
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesSave)
      # The list shortens when the daemon pushes the saved profile back as the
      # active one, which is also when the cursors are re-seeked.
      set_scene_profiles(model, profiles({"solo", ["Main", "Cam", "BRB Loop"]}).activate("solo"))

      model.scenes.map(&.name).should eq(["Utility Cam"])
      model.scene_cursor.should eq(0)
    end

    it "sends the whole draft to the daemon once, on the save and not the naming" do
      model = profile_model
      sent, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      # The draft starts holding `Utility Cam`; drop it and take `BRB Loop`, so
      # the sent list is the draft's own rather than what it opened with.
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 2)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 3)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)
      # Confirming a name is not a save: it must not reach the daemon.
      sent.should be_empty
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesSave)

      sent.size.should eq(1)
      command = sent.first
      command.name.should eq(Obsctl::IPC::CommandName::SAVE_SCENE_PROFILE)
      command.target.should eq("solo")
      command.hidden.should eq(["BRB Loop"])
      # Nothing is being renamed, so the key is left out entirely rather than
      # sent as null.
      command.rename_from.should be_nil
    end
  end

  describe "cycling saved profiles" do
    it "says so when there is nothing saved to cycle through" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesCycleNext)

      outcome.message.should eq("no saved scene profiles")
      model.scene_profile_editor.name.should eq("")
    end

    it "loads each saved profile in turn and names what is being edited" do
      model = profile_model
      set_scene_profiles(model, profiles({"streaming", ["BRB Loop"]}, {"editing", ["Cam"]}))
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)

      first = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesCycleNext)
      first.message.should eq("editing scene profile: streaming")
      model.scene_profile_editor.hidden.should eq(["BRB Loop"].to_set)

      second = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesCycleNext)
      second.message.should eq("editing scene profile: editing")
      model.scene_profile_editor.hidden.should eq(["Cam"].to_set)

      # And back round to the first, so the list is a ring rather than a wall.
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesCycleNext).message
        .should eq("editing scene profile: streaming")
    end

    it "starts from the end going backwards" do
      model = profile_model
      set_scene_profiles(model, profiles({"streaming", ["BRB Loop"]}, {"editing", ["Cam"]}))
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesCyclePrevious).message
        .should eq("editing scene profile: editing")
    end
  end

  describe "renaming" do
    it "renames the profile the draft came from instead of leaving a copy beside it" do
      model = profile_model
      set_scene_profiles(model, profiles({"streaming", ["BRB Loop"]}, {"editing", ["Cam"]}).activate("streaming"))
      sent, dispatcher = profile_dispatcher(model)
      # Opening on the active profile is what records where the draft came from.
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "live".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesSave)

      # One command, carrying both names: `rename_from` is what lets the daemon
      # move the entry where it stands, keeping its place in the list and its
      # hold on the active profile. A save-then-delete pair would rewrite the
      # config twice and switch filtering off on the way.
      sent.size.should eq(1)
      command = sent.first
      command.name.should eq(Obsctl::IPC::CommandName::SAVE_SCENE_PROFILE)
      command.target.should eq("live")
      command.rename_from.should eq("streaming")
      command.hidden.should eq(["BRB Loop"])
      model.scene_profile_editor.origin_name.should eq("live")
    end

    it "renames the profile Tab loaded, not the one that happened to be active" do
      model = profile_model
      set_scene_profiles(model, profiles({"streaming", ["BRB Loop"]}, {"editing", ["Cam"]}).activate("streaming"))
      sent, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      # One step off `streaming` lands on `editing`, so the draft's origin has
      # to have moved with it rather than staying on the profile in effect.
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesCycleNext)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "cutting".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesSave)

      command = sent.first
      command.rename_from.should eq("editing")
      command.target.should eq("cutting")
      command.hidden.should eq(["Cam"])
    end

    it "refuses a name that belongs to a different saved profile" do
      model = profile_model
      set_scene_profiles(model, profiles({"streaming", ["BRB Loop"]}, {"editing", ["Cam"]}).activate("streaming"))
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "editing".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)

      outcome.message.should eq("a scene profile named 'editing' already exists; open it from <leader>p to edit it")
      # The field stays open with the typed name in it, the way the empty-name
      # refusal already behaves: the reader gets to correct it in place.
      model.scene_profile_editor.naming.should be_true
      model.scene_profile_editor.name_input.should eq("editing")
      model.scene_profile_editor.name.should eq("streaming")
      # Nothing was replaced: `editing` still hides what it always hid.
      model.scene_profiles.profiles.map(&.name).should eq(["streaming", "editing"])
      model.scene_profiles.profiles.last.hidden.should eq(["Cam"].to_set)
    end

    it "allows confirming the name the draft already came from" do
      # Retyping a profile's own name is editing it, not colliding with it, so
      # the guard has to let this through or the editor could never be saved
      # after a Ctrl-U.
      model = profile_model
      set_scene_profiles(model, profiles({"streaming", ["BRB Loop"]}).activate("streaming"))
      sent, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 1)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "streaming".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      named = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesSave)

      named.message.should eq("scene profile named: streaming; press enter to save")
      command = sent.first
      command.target.should eq("streaming")
      command.hidden.should eq(["BRB Loop", "Cam"])
      # Saved under its own name, so it is an edit rather than a rename.
      command.rename_from.should be_nil
    end
  end

  describe "naming" do
    it "appends characters and removes one whole grapheme per backspace" do
      # A backspace measured in bytes or codepoints would leave half of a
      # multi-byte character behind, which is what `each_grapheme` avoids.
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "gró".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      model.scene_profile_editor.name_input.should eq("gró")

      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameBackspace)
      model.scene_profile_editor.name_input.should eq("gr")
    end

    it "does nothing on backspace over an empty field" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameBackspace)
      model.scene_profile_editor.name_input.should eq("")
    end

    it "clears the whole field on Ctrl-U" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameClearLine)
      model.scene_profile_editor.name_input.should eq("")
    end

    it "returns to the list with the draft intact when naming is cancelled" do
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene, index: 1)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      "sol".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCancel)

      model.scene_profile_editor.active.should be_true
      model.scene_profile_editor.naming.should be_false
      model.scene_profile_editor.name_input.should eq("")
      model.scene_profile_editor.hidden.should eq(["Utility Cam", "Cam"].to_set)
    end

    it "takes a pasted name, minus the control characters that would submit it" do
      # The same strip the palette does: a copied line ending arrives as a
      # carriage return, which would otherwise read as Enter and save the
      # profile under a half-pasted name.
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
      dispatcher.paste("late\rnight")

      model.scene_profile_editor.name_input.should eq("latenight")
    end

    it "leaves a paste alone while the editor is open but not naming" do
      # The list mode has no text field, so a paste there belongs to whatever
      # is behind the modal rather than silently seeding a name.
      model = profile_model
      _, dispatcher = profile_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
      dispatcher.paste("solo")

      model.scene_profile_editor.name_input.should eq("")
    end
  end

  it "sends nothing to the daemon for a whole open, toggle, name and save" do
    # Scene profiles are a dashboard-side filter. If any of this reached the
    # daemon it would be a protocol change, and the sibling implementations
    # would have to learn about profiles to stay compatible.
    model = profile_model
    sent, dispatcher = profile_dispatcher(model)
    act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfiles)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNavigateDown)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesToggleScene)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)
    "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameCharacter, character: char) }
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesNameSubmit)

    sent.should be_empty
  end
end
