require "../../spec_helper"

describe Obsctl::Domain::Volume do
  describe ".percent_to_mul" do
    it "converts volume percent linearly" do
      Obsctl::Domain::Volume.percent_to_mul(70).should eq(0.7)
    end
  end

  describe ".mul_to_percent" do
    it "converts an obs-websocket multiplier to the user-facing scale" do
      Obsctl::Domain::Volume.mul_to_percent(0.0).should eq(0)
      Obsctl::Domain::Volume.mul_to_percent(0.5).should eq(50)
      Obsctl::Domain::Volume.mul_to_percent(1.0).should eq(100)
    end

    # OBS allows gain above unity, which has no spelling on a 0-100 scale.
    it "clamps a multiplier above unity to 100" do
      Obsctl::Domain::Volume.mul_to_percent(2.5).should eq(100)
    end

    it "round-trips with percent_to_mul" do
      (0..100).each do |percent|
        mul = Obsctl::Domain::Volume.percent_to_mul(percent)
        Obsctl::Domain::Volume.mul_to_percent(mul).should eq(percent)
      end
    end
  end
end
