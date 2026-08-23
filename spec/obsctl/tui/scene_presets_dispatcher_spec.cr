require "../../spec_helper"
require "../../../src/obsctl/tui/dispatcher"

private ALL_SCENES = ["Main", "Cam", "Utility Cam", "BRB Loop"]

private def preset_model(names = ALL_SCENES, hidden = ["Utility Cam"])
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

private def preset_dispatcher(model, persister : Obsctl::TUI::Dispatcher::ScenePresetPersister? = nil)
  sent = [] of Obsctl::IPC::CommandPayload
  sender = ->(payload : Obsctl::IPC::CommandPayload) do
    sent << payload
    Obsctl::IPC::Response.new("test", true, JSON.parse(%({"message":"ok"})))
  end
  {sent, Obsctl::TUI::Dispatcher.new(model, sender, scene_preset_persister: persister)}
end

private def act(dispatcher, kind : Obsctl::TUI::ActionKind, index : Int32? = nil, character : Char? = nil)
  dispatcher.handle(Obsctl::TUI::Action.new(kind, character: character, index: index))
end

private def presets(*entries : Tuple(String, Array(String)))
  Obsctl::TUI::ScenePresets.new(entries.to_a.map { |(name, hidden)| Obsctl::TUI::ScenePreset.new(name, hidden.to_set) })
end

describe "scene preset editor dispatch" do
  describe "opening" do
    it "seeds the draft from the scenes the config already hides" do
      # Adopting presets must not move anything: the first draft is exactly
      # what the dashboard is drawing at the moment the editor opens.
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)

      editor = model.scene_preset_editor
      editor.active.should be_true
      editor.naming.should be_false
      editor.cursor.should eq(0)
      editor.name.should eq("")
      editor.hidden.should eq(["Utility Cam"].to_set)
      # Opening alone changes nothing the dashboard reads.
      model.scene_presets.presets.should be_empty
      model.scene_presets.active.should be_nil
    end

    it "seeds the draft from the active preset when there is one" do
      model = preset_model
      model.scene_presets = presets({"streaming", ["BRB Loop"]}).activate("streaming")
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)

      model.scene_preset_editor.name.should eq("streaming")
      model.scene_preset_editor.hidden.should eq(["BRB Loop"].to_set)
    end

    it "refuses to open with no scenes, because it would swallow keys for nothing" do
      model = preset_model([] of String, [] of String)
      _, dispatcher = preset_dispatcher(model)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)

      model.scene_preset_editor.active.should be_false
      outcome.message.should eq("no scenes to configure")
    end
  end

  describe "toggling" do
    it "toggles the cursor row both ways" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene)
      model.scene_preset_editor.hidden.should eq(["Utility Cam", "Main"].to_set)

      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene)
      model.scene_preset_editor.hidden.should eq(["Utility Cam"].to_set)
    end

    it "moves the cursor to the row a click named and toggles that one" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: 3)

      model.scene_preset_editor.cursor.should eq(3)
      model.scene_preset_editor.hidden.should eq(["Utility Cam", "BRB Loop"].to_set)
    end

    it "ignores a row that is not there" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: 99)

      model.scene_preset_editor.hidden.should eq(["Utility Cam"].to_set)
    end

    it "lists hidden scenes too, so a toggle can bring one back" do
      # Row 2 is `Utility Cam`, which the dashboard is not drawing. The editor
      # is the one surface that shows it, and `t` on it is the way back.
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: 2)

      model.scene_preset_editor.hidden.should be_empty
    end

    it "clamps the cursor at both ends instead of wrapping" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      3.times { act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNavigateUp) }
      model.scene_preset_editor.cursor.should eq(0)
      9.times { act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNavigateDown) }
      model.scene_preset_editor.cursor.should eq(ALL_SCENES.size - 1)
    end

    it "does not change what the dashboard draws until the draft is saved" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: 0)

      model.scenes.map(&.name).should eq(["Main", "Cam", "BRB Loop"])
      model.scene_presets.presets.should be_empty
    end
  end

  describe "cancelling" do
    it "leaves the visible scenes and the saved presets exactly as they were" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: 0)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::CloseScenePresets)

      model.scene_preset_editor.active.should be_false
      model.scenes.map(&.name).should eq(["Main", "Cam", "BRB Loop"])
      model.scene_presets.presets.should be_empty
      model.scene_presets.active.should be_nil
      outcome.message.should eq("scene preset editing cancelled")
    end
  end

  describe "saving" do
    it "asks for a name rather than failing when the draft has none" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsSave)

      model.scene_preset_editor.active.should be_true
      model.scene_preset_editor.naming.should be_true
      model.scene_presets.presets.should be_empty
      outcome.message.should eq("name this scene preset")
    end

    it "refuses a name that is only whitespace" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      "  ".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCharacter, character: char) }
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameSubmit)

      outcome.message.should eq("scene preset name cannot be empty")
      model.scene_preset_editor.naming.should be_true
      model.scene_presets.presets.should be_empty
    end

    # Naming and saving are two steps, which is what the box says on screen:
    # the list hint offers "n name" and "enter save" separately, and the naming
    # hint reads "enter confirm". If confirming a name also saved, it would
    # close the modal, and the `Enter` the hint asks for next would reach the
    # dashboard and switch the live OBS scene.
    it "confirms a name without writing anything, leaving the modal open" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCharacter, character: char) }
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameSubmit)

      model.scene_preset_editor.active.should be_true
      model.scene_preset_editor.naming.should be_false
      model.scene_preset_editor.name.should eq("solo")
      model.scene_preset_editor.name_input.should eq("")
      model.scene_presets.presets.should be_empty
      model.scene_presets.active.should be_nil
      outcome.message.should eq("scene preset named: solo; press enter to save")
    end

    it "saves the draft, activates it, closes the modal, and filters the scene list" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      # Hide `Cam` on top of the `Utility Cam` the draft started with, and
      # bring `Utility Cam` back, so the saved set is neither the old one nor
      # the whole list.
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: 1)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: 2)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameSubmit)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsSave)

      model.scene_preset_editor.active.should be_false
      model.scene_preset_editor.naming.should be_false
      model.scene_presets.active.should eq("solo")
      model.scene_presets.presets.map(&.name).should eq(["solo"])
      model.scene_presets.presets.first.hidden_scenes.should eq(["Cam"].to_set)
      # An active preset is the whole answer: `Utility Cam` is drawn again even
      # though the snapshot still flags it hidden.
      model.scenes.map(&.name).should eq(["Main", "Utility Cam", "BRB Loop"])
      outcome.message.should eq("scene preset saved: solo")
    end

    it "replaces a preset of the same name instead of adding a second one" do
      model = preset_model
      model.scene_presets = presets({"streaming", ["BRB Loop"]}, {"editing", [] of String}).activate("streaming")
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: 1)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsSave)

      model.scene_presets.presets.map(&.name).should eq(["streaming", "editing"])
      model.scene_presets.presets.first.hidden_scenes.should eq(["BRB Loop", "Cam"].to_set)
    end

    it "brings cursors back inside a scene list that just got shorter" do
      model = preset_model
      model.scene_cursor = 3
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      ALL_SCENES.each_index { |index| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: index) }
      # Only `Main` survives: the draft started holding `Utility Cam`, so
      # toggling every row hides the other three and unhides that one.
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameSubmit)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsSave)

      model.scenes.map(&.name).should eq(["Utility Cam"])
      model.scene_cursor.should eq(0)
    end

    it "reports what the persister said, and is handed the saved presets once" do
      model = preset_model
      seen = [] of Obsctl::TUI::ScenePresets
      persister = ->(saved : Obsctl::TUI::ScenePresets) do
        seen << saved
        "scene preset saved to config"
      end
      _, dispatcher = preset_dispatcher(model, persister)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameSubmit)
      # The persister is handed the presets by the save, not by the naming:
      # confirming a name must not reach the config file.
      seen.should be_empty
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsSave)

      seen.size.should eq(1)
      seen.first.active.should eq("solo")
      seen.first.presets.map(&.name).should eq(["solo"])
      outcome.message.should eq("scene preset saved to config")
    end
  end

  describe "cycling saved presets" do
    it "says so when there is nothing saved to cycle through" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsCycleNext)

      outcome.message.should eq("no saved scene presets")
      model.scene_preset_editor.name.should eq("")
    end

    it "loads each saved preset in turn and names what is being edited" do
      model = preset_model
      model.scene_presets = presets({"streaming", ["BRB Loop"]}, {"editing", ["Cam"]})
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)

      first = act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsCycleNext)
      first.message.should eq("editing scene preset: streaming")
      model.scene_preset_editor.hidden.should eq(["BRB Loop"].to_set)

      second = act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsCycleNext)
      second.message.should eq("editing scene preset: editing")
      model.scene_preset_editor.hidden.should eq(["Cam"].to_set)

      # And back round to the first, so the list is a ring rather than a wall.
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsCycleNext).message
        .should eq("editing scene preset: streaming")
    end

    it "starts from the end going backwards" do
      model = preset_model
      model.scene_presets = presets({"streaming", ["BRB Loop"]}, {"editing", ["Cam"]})
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsCyclePrevious).message
        .should eq("editing scene preset: editing")
    end
  end

  describe "naming" do
    it "appends characters and removes one whole grapheme per backspace" do
      # A backspace measured in bytes or codepoints would leave half of a
      # multi-byte character behind, which is what `each_grapheme` avoids.
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      "gró".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCharacter, character: char) }
      model.scene_preset_editor.name_input.should eq("gró")

      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameBackspace)
      model.scene_preset_editor.name_input.should eq("gr")
    end

    it "does nothing on backspace over an empty field" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameBackspace)
      model.scene_preset_editor.name_input.should eq("")
    end

    it "clears the whole field on Ctrl-U" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameClearLine)
      model.scene_preset_editor.name_input.should eq("")
    end

    it "returns to the list with the draft intact when naming is cancelled" do
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene, index: 1)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      "sol".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCharacter, character: char) }
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCancel)

      model.scene_preset_editor.active.should be_true
      model.scene_preset_editor.naming.should be_false
      model.scene_preset_editor.name_input.should eq("")
      model.scene_preset_editor.hidden.should eq(["Utility Cam", "Cam"].to_set)
    end

    it "takes a pasted name, minus the control characters that would submit it" do
      # The same strip the palette does: a copied line ending arrives as a
      # carriage return, which would otherwise read as Enter and save the
      # preset under a half-pasted name.
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
      dispatcher.paste("late\rnight")

      model.scene_preset_editor.name_input.should eq("latenight")
    end

    it "leaves a paste alone while the editor is open but not naming" do
      # The list mode has no text field, so a paste there belongs to whatever
      # is behind the modal rather than silently seeding a name.
      model = preset_model
      _, dispatcher = preset_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
      dispatcher.paste("solo")

      model.scene_preset_editor.name_input.should eq("")
    end
  end

  it "sends nothing to the daemon for a whole open, toggle, name and save" do
    # Scene presets are a dashboard-side filter. If any of this reached the
    # daemon it would be a protocol change, and the sibling implementations
    # would have to learn about presets to stay compatible.
    model = preset_model
    sent, dispatcher = preset_dispatcher(model)
    act(dispatcher, Obsctl::TUI::ActionKind::OpenScenePresets)
    act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNavigateDown)
    act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsToggleScene)
    act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsBeginNaming)
    "solo".each_char { |char| act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameCharacter, character: char) }
    act(dispatcher, Obsctl::TUI::ActionKind::ScenePresetsNameSubmit)

    sent.should be_empty
  end
end
