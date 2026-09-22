require "../../spec_helper"
require "../../support/scene_profiles"
require "../../../src/obsctl/tui/dispatcher"

private LIST_SCENES = ["Main", "Cam", "Utility Cam", "BRB Loop"]

private def list_model(names = LIST_SCENES)
  model = Obsctl::TUI::Model.new
  model.connected_to_daemon = true
  model.snapshot = Obsctl::State::ObsSnapshot.new(
    connected: true,
    obs_studio_version: "31.0.0",
    obs_websocket_version: "5.5.0",
    current_scene: names.first?,
    scenes: names.map_with_index do |name, index|
      Obsctl::State::SceneState.new(name, active: index == 0, hidden: false)
    end,
    audio_inputs: [] of Obsctl::State::AudioState
  )
  model
end

private def list_dispatcher(model)
  sent = [] of Obsctl::IPC::CommandPayload
  sender = ->(payload : Obsctl::IPC::CommandPayload) do
    sent << payload
    Obsctl::IPC::Response.new("test", true, JSON.parse(%({"message":"ok"})))
  end
  {sent, Obsctl::TUI::Dispatcher.new(model, sender)}
end

private def act(dispatcher, kind : Obsctl::TUI::ActionKind, index : Int32? = nil)
  dispatcher.handle(Obsctl::TUI::Action.new(kind, index: index))
end

private def saved_profiles(*entries : Tuple(String, Array(String)), active : String? = nil)
  scene_profiles_fixture(entries.to_a, active)
end

private def two_profiles(active : String? = nil)
  saved_profiles({"streaming", ["BRB Loop"]}, {"editing", ["Cam", "BRB Loop"]}, active: active)
end

# The scene-profile commands the dispatcher put on the wire, in order. The
# dashboard no longer writes the config file for these -- it asks the daemon --
# so what a branch did is visible here rather than in a persister.
private def scene_profile_commands(sent)
  sent.select(&.name.includes?("scene_profile"))
end

describe "scene profile list dispatch" do
  describe "opening" do
    it "starts the cursor on the profile that is in effect" do
      model = list_model
      set_scene_profiles(model, two_profiles(active: "editing"))
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)

      model.scene_profile_list.active.should be_true
      model.scene_profile_list.confirming.should be_false
      # Row 0 is "show every scene", so the second saved profile is row 2.
      model.scene_profile_list.cursor.should eq(2)
    end

    it "starts on the show-every-scene row when no profile is in effect" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)

      model.scene_profile_list.cursor.should eq(0)
    end

    it "opens with nothing saved, because that is where a first profile is made" do
      # Unlike the scene picker, which refuses to open on an empty list: this
      # modal always has its show-every-scene row and its `n` key, so it is
      # never a dead end.
      model = list_model
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)

      model.scene_profile_list.active.should be_true
      model.scene_profile_list_entries.map(&.name).should eq([Obsctl::TUI::SceneProfileList::SHOW_EVERY_SCENE])
    end
  end

  describe "activating" do
    it "names the row under the cursor and closes the list" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      sent, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListActivate)

      scene_profile_commands(sent).map(&.target).should eq(["streaming"])
      model.scene_profile_list.active.should be_false
    end

    it "activates the row a digit names, whatever the cursor is on" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      sent, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 2)

      scene_profile_commands(sent).map(&.target).should eq(["editing"])
    end

    it "filters the scene list once the daemon's answer arrives, not before" do
      # The dashboard does not apply the filter itself any more: it asks, and
      # the scene list changes when the daemon pushes a snapshot whose scenes
      # carry the resolved `hidden` flag. Asserting both halves here is what
      # would catch a dashboard that went back to deciding for itself.
      model = list_model
      set_scene_profiles(model, two_profiles)
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 2)

      model.scenes.map(&.name).should eq(LIST_SCENES)

      set_scene_profiles(model, two_profiles(active: "editing"))

      model.scene_profiles.active.should eq("editing")
      model.scenes.map(&.name).should eq(["Main", "Utility Cam"])
    end

    it "clears from row 0 without forgetting the saved profiles" do
      model = list_model
      set_scene_profiles(model, two_profiles(active: "editing"))
      sent, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 0)

      scene_profile_commands(sent).map(&.name).should eq([Obsctl::IPC::CommandName::CLEAR_SCENE_PROFILE])
      model.scene_profile_list.active.should be_false

      set_scene_profiles(model, two_profiles)

      model.scene_profiles.active.should be_nil
      model.scene_profiles.profiles.map(&.name).should eq(["streaming", "editing"])
      model.scenes.map(&.name).should eq(LIST_SCENES)
    end

    it "brings cursors back inside a scene list that just got shorter" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      model.scene_cursor = 3
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 2)
      set_scene_profiles(model, two_profiles(active: "editing"))
      model.clamp_cursors

      model.scenes.size.should eq(2)
      model.scene_cursor.should eq(1)
    end

    it "asks the daemon once, naming the profile the cursor is on" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      sent, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      # Opening and moving ask the daemon nothing; only the activation does.
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
      scene_profile_commands(sent).should be_empty
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListActivate)

      commands = scene_profile_commands(sent)
      commands.size.should eq(1)
      commands.first.name.should eq(Obsctl::IPC::CommandName::SET_SCENE_PROFILE)
      commands.first.target.should eq("streaming")
    end

    it "clears rather than sets when the row is 'show every scene'" do
      # Its own command, not a set with an empty target: a blank target is a
      # malformed payload and a sentinel name would collide with a profile a
      # user is entitled to create.
      model = list_model
      set_scene_profiles(model, two_profiles(active: "streaming"))
      sent, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 0)

      commands = scene_profile_commands(sent)
      commands.size.should eq(1)
      commands.first.name.should eq(Obsctl::IPC::CommandName::CLEAR_SCENE_PROFILE)
      commands.first.target.should be_nil
    end

    it "ignores a row that is not there" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      sent, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 9)

      model.scene_profiles.active.should be_nil
      model.scene_profile_list.active.should be_true
      scene_profile_commands(sent).should be_empty
    end

    it "reports a daemon that has gone away instead of tearing the dashboard down" do
      # A closed socket makes the IPC client raise `ServerUnavailable`, and a
      # daemon that stops answering makes it raise `RequestTimeout`. Neither is
      # an `IO::Error`, so nothing above the dispatcher would catch either one
      # -- the dashboard would exit with a backtrace mid-keypress. Every other
      # command turns them into a status line, and so must this one.
      model = list_model
      set_scene_profiles(model, two_profiles)
      dispatcher = Obsctl::TUI::Dispatcher.new(
        model,
        ->(_payload : Obsctl::IPC::CommandPayload) { raise Obsctl::Domain::ServerUnavailable.new }
      )
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 1)

      outcome.message.should eq("error: obsctl server is not running")
    end
  end

  describe "closing" do
    it "leaves the profiles alone and disarms a pending delete" do
      model = list_model
      set_scene_profiles(model, two_profiles(active: "streaming"))
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeletePrompt)
      act(dispatcher, Obsctl::TUI::ActionKind::CloseSceneProfileList)

      model.scene_profile_list.active.should be_false
      model.scene_profile_list.confirming.should be_false
      model.scene_profiles.active.should eq("streaming")
      model.scene_profiles.profiles.size.should eq(2)
    end
  end

  describe "editing from the list" do
    it "hands the chosen profile to the editor without putting it into effect" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 0)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListEdit)

      editor = model.scene_profile_editor
      editor.active.should be_true
      editor.naming.should be_false
      editor.name.should eq("editing")
      editor.hidden.should eq(["Cam", "BRB Loop"].to_set)
      # Only one modal may be open: both capture every key.
      model.scene_profile_list.active.should be_false
      # Editing is not activating -- nothing the dashboard draws has changed.
      model.scene_profiles.active.should be_nil
      model.scenes.map(&.name).should eq(LIST_SCENES)
      outcome.message.should eq("editing scene profile: editing")
    end

    it "opens the name field straight away for a rename" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListRename)

      editor = model.scene_profile_editor
      editor.naming.should be_true
      # Seeded, not blank: the field takes the place of the title badge while
      # it is open, so the old name would otherwise be nowhere on screen.
      editor.name_input.should eq("streaming")
      editor.name.should eq("streaming")
      outcome.message.should eq("rename scene profile: streaming")
    end

    it "starts `n` on a draft of its own instead of the profile in effect" do
      # Creating a second profile used to begin by overwriting the active one,
      # because the editor always seeded itself from it.
      model = list_model
      set_scene_profiles(model, two_profiles(active: "streaming"))
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNew)

      editor = model.scene_profile_editor
      editor.active.should be_true
      editor.name.should eq("")
      editor.hidden.should be_empty
      model.scene_profile_list.active.should be_false
      outcome.message.should eq("new scene profile: toggle scenes, then n to name it")
    end

    it "says the show-every-scene row is not a profile instead of editing it" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListEdit)

      outcome.message.should eq("'Show every scene' is not a profile, so there is nothing to edit")
      model.scene_profile_editor.active.should be_false
      model.scene_profile_list.active.should be_true
    end
  end

  describe "deleting" do
    it "asks the daemon to delete on the second `d`, and only then" do
      model = list_model
      set_scene_profiles(model, two_profiles(active: "streaming"))
      sent, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      armed = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeletePrompt)

      # Arming is not deleting: the first press only asks.
      armed.message.should eq("delete scene profile 'streaming'? press d again to confirm")
      model.scene_profile_list.confirming.should be_true
      scene_profile_commands(sent).should be_empty

      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeleteConfirm)

      commands = scene_profile_commands(sent)
      commands.size.should eq(1)
      commands.first.name.should eq(Obsctl::IPC::CommandName::DELETE_SCENE_PROFILE)
      commands.first.target.should eq("streaming")
      model.scene_profile_list.confirming.should be_false
    end

    it "disarms without deleting when anything else is pressed" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      sent, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
      act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeletePrompt)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeleteCancel)

      outcome.message.should eq("delete cancelled")
      model.scene_profile_list.confirming.should be_false
      model.scene_profile_list.active.should be_true
      model.scene_profiles.profiles.size.should eq(2)
      scene_profile_commands(sent).should be_empty
    end

    it "says the show-every-scene row is not a profile instead of arming" do
      model = list_model
      set_scene_profiles(model, two_profiles)
      _, dispatcher = list_dispatcher(model)
      act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
      outcome = act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeletePrompt)

      outcome.message.should eq("'Show every scene' is not a profile, so there is nothing to delete")
      model.scene_profile_list.confirming.should be_false
      model.scene_profiles.profiles.size.should eq(2)
    end
  end

  it "reaches OBS for none of it, asking the daemon for scene profiles only" do
    # The architecture boundary in one example. Scene profiles are obsctl's own
    # config, so every branch here goes to a `*_scene_profile` command and none
    # of them is an OBS request like `set_scene`.
    model = list_model
    set_scene_profiles(model, two_profiles)
    sent, dispatcher = list_dispatcher(model)
    act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListActivate)
    act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListEdit)
    act(dispatcher, Obsctl::TUI::ActionKind::CloseSceneProfiles)
    act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeletePrompt)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeleteConfirm)
    act(dispatcher, Obsctl::TUI::ActionKind::CloseSceneProfileList)

    sent.map(&.name).should eq([
      Obsctl::IPC::CommandName::SET_SCENE_PROFILE,
      Obsctl::IPC::CommandName::DELETE_SCENE_PROFILE,
    ])
  end
end

describe "scene profile activation and the scene cursors" do
  it "keeps the highlight on the scene it was on when the filter shortens the list" do
    # The cursors are indexes into the visible scene list, and activating a
    # profile makes that a different list. Clamping alone would leave row 2
    # highlighted while row 2 now names another scene -- and the next Enter
    # would tell OBS to switch to it.
    model = list_model
    set_scene_profiles(model, saved_profiles({"streaming", ["Main"]}))
    model.set_cursor(Obsctl::TUI::FocusPanel::Scenes, 2) # "Utility Cam"
    model.scene_picker_cursor = 3                        # "BRB Loop"
    _, dispatcher = list_dispatcher(model)

    act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
    act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 1)
    # The daemon's answer: the scene list shortens here, which is the moment
    # the cursors have to be re-seeked.
    set_scene_profiles(model, saved_profiles({"streaming", ["Main"]}, active: "streaming"))

    model.scene_profiles.active.should eq("streaming")
    model.scenes.map(&.name).should eq(["Cam", "Utility Cam", "BRB Loop"])
    model.focused_scene.try(&.name).should eq("Utility Cam")
    model.scenes[model.scene_picker_cursor].name.should eq("BRB Loop")
  end

  it "falls back to a clamped cursor when the profile hides the focused scene" do
    model = list_model
    set_scene_profiles(model, saved_profiles({"solo", ["Cam", "Utility Cam", "BRB Loop"]}))
    model.set_cursor(Obsctl::TUI::FocusPanel::Scenes, 3) # "BRB Loop", about to be hidden
    _, dispatcher = list_dispatcher(model)

    act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
    act(dispatcher, Obsctl::TUI::ActionKind::PickSceneProfile, index: 1)
    set_scene_profiles(model, saved_profiles({"solo", ["Cam", "Utility Cam", "BRB Loop"]}, active: "solo"))

    model.scenes.map(&.name).should eq(["Main"])
    model.focused_scene.try(&.name).should eq("Main")
  end

  it "restores the highlight by name when deleting the active profile grows the list back" do
    model = list_model
    set_scene_profiles(model, saved_profiles({"streaming", ["Main"]}, active: "streaming"))
    model.set_cursor(Obsctl::TUI::FocusPanel::Scenes, 0) # "Cam" while filtered
    _, dispatcher = list_dispatcher(model)

    act(dispatcher, Obsctl::TUI::ActionKind::OpenSceneProfileList)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListNavigateDown)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeletePrompt)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListDeleteConfirm)
    # The daemon deletes the profile, which was the active one, so filtering
    # goes off and the scene list grows back.
    set_scene_profiles(model, Obsctl::TUI::SceneProfiles.empty)

    model.scenes.map(&.name).should eq(LIST_SCENES)
    model.focused_scene.try(&.name).should eq("Cam")
  end
end

describe "scene profile editor guards" do
  it "refuses every route into the editor while the daemon has reported no scenes" do
    # The editor captures the whole keyboard and draws nothing at all for an
    # empty scene list, so opening it here would look like a frozen dashboard.
    [
      Obsctl::TUI::ActionKind::OpenSceneProfiles,
      Obsctl::TUI::ActionKind::SceneProfileListNew,
      Obsctl::TUI::ActionKind::SceneProfileListEdit,
      Obsctl::TUI::ActionKind::SceneProfileListRename,
    ].each do |kind|
      model = list_model([] of String)
      set_scene_profiles(model, saved_profiles({"streaming", ["BRB Loop"]}))
      model.scene_profile_list.cursor = 1
      _, dispatcher = list_dispatcher(model)

      outcome = act(dispatcher, kind)

      model.scene_profile_editor.active.should be_false
      outcome.message.should eq("no scenes to configure"), "#{kind} opened the editor on an empty scene list"
    end
  end

  it "opens a rename with the current name already in the field" do
    # While the name field is up it replaces the title badge, so a blank field
    # would mean retyping the name with the old one nowhere on screen.
    model = list_model
    set_scene_profiles(model, two_profiles)
    model.scene_profile_list.cursor = 1
    _, dispatcher = list_dispatcher(model)

    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListRename)

    model.scene_profile_editor.naming.should be_true
    model.scene_profile_editor.name_input.should eq("streaming")
  end

  it "still starts a fresh name blank when `n` names a draft inside the editor" do
    model = list_model
    set_scene_profiles(model, two_profiles)
    model.scene_profile_list.cursor = 1
    _, dispatcher = list_dispatcher(model)

    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfileListEdit)
    act(dispatcher, Obsctl::TUI::ActionKind::SceneProfilesBeginNaming)

    model.scene_profile_editor.name_input.should eq("")
  end
end
