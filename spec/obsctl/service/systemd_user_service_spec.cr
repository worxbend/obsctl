require "../../spec_helper"
require "../../../src/obsctl/service/systemd_user_service"

describe Obsctl::Service::SystemdUserService do
  it "renders a user service with an absolute headless ExecStart" do
    unit = Obsctl::Service::SystemdUserService.new("/opt/obsctl/bin/obsctl").render

    unit.should contain("Description=obsctl OBS WebSocket control daemon")
    unit.should contain("ExecStart=/opt/obsctl/bin/obsctl server --headless")
    unit.should contain("Restart=on-failure")
    unit.should contain("StartLimitIntervalSec=0")
    unit.should contain("WantedBy=graphical-session.target")
    unit.should_not contain("Wants=graphical-session.target")
  end

  it "resolves the user service path from HOME" do
    env = {"HOME" => "/tmp/example-home"}

    Obsctl::Service::SystemdUserService.default_path(env).should eq("/tmp/example-home/.config/systemd/user/obsctl.service")
  end
end
