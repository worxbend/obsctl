require "../../../spec_helper"
require "../../../../src/obsctl/obs/protocol/obs_event"

private def raw(event_type : String, data : Hash? = nil)
  Obsctl::OBS::Protocol::Event.new(event_type, data.try { |payload| JSON.parse(payload.to_json) })
end

private alias ObsEvent = Obsctl::OBS::Protocol::ObsEvent

describe Obsctl::OBS::Protocol::ObsEvent do
  describe "scene events" do
    it "reads the new program scene" do
      translated = ObsEvent.from(raw("CurrentProgramSceneChanged", {"sceneName" => "Main"}))
      translated.should be_a(ObsEvent::ProgramSceneChanged)
      translated.as(ObsEvent::ProgramSceneChanged).scene_name.should eq("Main")
    end

    it "ignores a scene change with no scene name" do
      ObsEvent.from(raw("CurrentProgramSceneChanged", {"unrelated" => 1})).should be_nil
    end

    it "treats every scene-list mutation as the same re-read" do
      %w[SceneListChanged SceneCreated SceneRemoved SceneNameChanged].each do |event_type|
        ObsEvent.from(raw(event_type)).should be_a(ObsEvent::SceneListChanged)
      end
    end
  end

  describe "input events" do
    it "reads a mute change" do
      translated = ObsEvent.from(raw("InputMuteStateChanged", {"inputName" => "Mic", "inputMuted" => true}))
      translated.as(ObsEvent::InputMuteChanged).input_name.should eq("Mic")
      translated.as(ObsEvent::InputMuteChanged).muted.should be_true
    end

    it "ignores a mute change that does not say what the new state is" do
      ObsEvent.from(raw("InputMuteStateChanged", {"inputName" => "Mic"})).should be_nil
    end

    # The reason this layer exists: OBS sends a volume of exactly 1 as the JSON
    # integer `1` and everything else as a float. Both are the same quantity,
    # and callers should never have to know that.
    it "reads an integer volume as a float" do
      translated = ObsEvent.from(raw("InputVolumeChanged", {"inputName" => "Mic", "inputVolumeMul" => 1}))
      translated.as(ObsEvent::InputVolumeChanged).volume_mul.should eq(1.0)
    end

    it "reads a fractional volume" do
      translated = ObsEvent.from(raw("InputVolumeChanged", {"inputName" => "Mic", "inputVolumeMul" => 0.5}))
      translated.as(ObsEvent::InputVolumeChanged).volume_mul.should eq(0.5)
    end

    it "passes through a volume level OBS omitted" do
      translated = ObsEvent.from(raw("InputVolumeChanged", {"inputName" => "Mic", "inputVolumeMul" => 0.5}))
      translated.as(ObsEvent::InputVolumeChanged).volume_db.should be_nil
    end

    it "treats every input-list mutation as the same re-read" do
      %w[InputCreated InputRemoved InputNameChanged].each do |event_type|
        ObsEvent.from(raw(event_type)).should be_a(ObsEvent::InputListChanged)
      end
    end
  end

  describe "output events" do
    it "reads stream and record state" do
      ObsEvent.from(raw("StreamStateChanged", {"outputActive" => true}))
        .as(ObsEvent::StreamStateChanged).active.should be_true
      ObsEvent.from(raw("RecordStateChanged", {"outputActive" => false}))
        .as(ObsEvent::RecordStateChanged).active.should be_false
    end

    it "ignores an output event that does not say whether the output is active" do
      ObsEvent.from(raw("StreamStateChanged", {"outputPath" => "/tmp/x.mkv"})).should be_nil
    end
  end

  it "treats profile and scene-collection changes as one studio-context change" do
    %w[CurrentProfileChanged ProfileListChanged
      CurrentSceneCollectionChanged SceneCollectionListChanged].each do |event_type|
      ObsEvent.from(raw(event_type)).should be_a(ObsEvent::StudioContextChanged)
    end
  end

  it "ignores event types obsctl does not track" do
    ObsEvent.from(raw("VendorEvent", {"vendorName" => "whatever"})).should be_nil
  end

  it "ignores a tracked event that arrived with no payload at all" do
    ObsEvent.from(raw("InputVolumeChanged")).should be_nil
  end
end
