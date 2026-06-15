require "../../spec_helper"

describe Obsctl::OBS::Auth do
  it "generates obs-websocket authentication hash" do
    Obsctl::OBS::Auth.authentication("password", "salt", "challenge").should eq("zTM5ki6L2vVvBQiTG9ckH1Lh64AbnCf6XZ226UmnkIA=")
  end
end
