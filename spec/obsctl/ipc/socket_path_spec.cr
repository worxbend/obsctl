require "../../spec_helper"
require "../../../src/obsctl/ipc/socket_path"

describe Obsctl::IPC::SocketPath do
  it "uses configured socket paths verbatim after expansion" do
    Obsctl::IPC::SocketPath.resolve("~/obsctl.sock").should eq(File.expand_path("~/obsctl.sock"))
  end

  it "uses XDG_RUNTIME_DIR when available" do
    env = {"XDG_RUNTIME_DIR" => "/run/user/1000"}

    Obsctl::IPC::SocketPath.resolve(nil, env).should eq("/run/user/1000/obsctl/obsctl.sock")
  end

  it "falls back to a per-user tmp path" do
    Obsctl::IPC::SocketPath.resolve(nil, {} of String => String).should contain("/tmp/obsctl-")
    Obsctl::IPC::SocketPath.resolve(nil, {} of String => String).should end_with("/obsctl.sock")
  end
end
