require "../../spec_helper"
require "../../../src/obsctl/obs/requests/audio"
require "../../../src/obsctl/obs/requests/scenes"

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
    response = Obsctl::OBS::Protocol::Response.from_frame(frame).not_nil!
    response.request_id.should eq("abc")
    response.response_data.not_nil!["obsVersion"].as_s.should eq("1")
  end
end
