require "../../spec_helper"
require "../../../src/obsctl/obs/protocol/event_subscription"
require "../../../src/obsctl/obs/requests/audio"
require "../../../src/obsctl/obs/requests/scenes"

describe Obsctl::OBS::Protocol::EventSubscription do
  it "defines the server event subscription mask explicitly" do
    mask = Obsctl::OBS::Protocol::EventSubscription::SERVER_DEFAULT

    mask.should eq(
      Obsctl::OBS::Protocol::EventSubscription::GENERAL |
      Obsctl::OBS::Protocol::EventSubscription::CONFIG |
      Obsctl::OBS::Protocol::EventSubscription::SCENES |
      Obsctl::OBS::Protocol::EventSubscription::INPUTS |
      Obsctl::OBS::Protocol::EventSubscription::OUTPUTS |
      Obsctl::OBS::Protocol::EventSubscription::INPUT_VOLUME_METERS
    )
  end

  it "subscribes to the output events that carry stream and record state" do
    mask = Obsctl::OBS::Protocol::EventSubscription::SERVER_DEFAULT

    # Dropping this bit does not break a build or a handler; it just stops
    # StreamStateChanged from ever arriving, so a stream started in the OBS UI
    # never reaches the dashboard.
    (mask & Obsctl::OBS::Protocol::EventSubscription::OUTPUTS).should_not eq(0)
    (mask & Obsctl::OBS::Protocol::EventSubscription::CONFIG).should_not eq(0)
  end

  it "subscribes to volume meters so the dashboard has meter data to draw" do
    mask = Obsctl::OBS::Protocol::EventSubscription::SERVER_DEFAULT

    # The supervisor itself ignores this category; the bit exists purely so the
    # events reach IPC subscribers. Without it the TUI's whole meter path —
    # `EventApplier#apply_obs_event`, `Model#record_meter_level`, the mixer
    # widget — is unreachable and the meters read silent forever.
    (mask & Obsctl::OBS::Protocol::EventSubscription::INPUT_VOLUME_METERS).should_not eq(0)
  end

  it "leaves unused high-volume categories out of the server mask" do
    mask = Obsctl::OBS::Protocol::EventSubscription::SERVER_DEFAULT

    (mask & Obsctl::OBS::Protocol::EventSubscription::SCENE_ITEM_TRANSFORM_CHANGED).should eq(0)
  end
end

describe Obsctl::OBS::Protocol::Request do
  it "serializes request frames" do
    frame = Obsctl::OBS::Protocol::Request.new("GetVersion", "1").to_frame
    frame.should contain(%("op":6))
    frame.should contain(%("requestType":"GetVersion"))
  end
end

describe Obsctl::OBS::Requests::Audio do
  it "serializes mute and volume request data" do
    mute = Obsctl::OBS::Requests::Audio.set_mute("Mic/Aux", true)
    mute["inputName"].as_s.should eq("Mic/Aux")
    mute["inputMuted"].as_bool.should be_true

    volume = Obsctl::OBS::Requests::Audio.set_volume("Mic/Aux", 0.7)
    volume["inputName"].as_s.should eq("Mic/Aux")
    volume["inputVolumeMul"].as_f.should eq(0.7)
  end
end

describe Obsctl::OBS::Requests::Scenes do
  it "serializes set current scene request data" do
    data = Obsctl::OBS::Requests::Scenes.set_current_program_scene("Main Camera")
    data["sceneName"].as_s.should eq("Main Camera")
  end
end

describe Obsctl::OBS::Protocol::Response do
  it "matches request responses by request id" do
    frame = %({"op":7,"d":{"requestType":"GetVersion","requestId":"abc","requestStatus":{"result":true,"code":100},"responseData":{"obsVersion":"1"}}})
    response = Obsctl::OBS::Protocol::Response.from_data(JSON.parse(frame))
    response.request_id.should eq("abc")
    response.response_data.not_nil!["obsVersion"].as_s.should eq("1")
  end
end
