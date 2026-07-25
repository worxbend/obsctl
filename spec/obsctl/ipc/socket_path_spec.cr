require "file_utils"
require "../../spec_helper"
require "../../../src/obsctl/ipc/socket_path"

private def with_socket_parent_tmpdir(&)
  root = File.join(Dir.tempdir, "obsctl-socket-parent-#{Random.rand(1_000_000)}")
  Dir.mkdir_p(root)
  yield root
ensure
  FileUtils.rm_rf(root) if root
end

private def socket_parent_mode(path : String) : Int32
  (File.info(path).permissions.value & 0o777).to_i32
end

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

  describe ".ensure_parent" do
    it "creates the socket directory owner-only" do
      with_socket_parent_tmpdir do |root|
        path = File.join(root, "obsctl", "obsctl.sock")

        Obsctl::IPC::SocketPath.ensure_parent(path)

        Dir.exists?(File.dirname(path)).should be_true
        socket_parent_mode(File.dirname(path)).should eq(0o700)
      end
    end

    # A configured socket_path may deliberately point into a directory obsctl
    # does not own, so an existing directory keeps whatever mode it has.
    it "leaves an existing directory's mode alone" do
      with_socket_parent_tmpdir do |root|
        parent = File.join(root, "obsctl")
        Dir.mkdir_p(parent)
        File.chmod(parent, 0o755)

        Obsctl::IPC::SocketPath.ensure_parent(File.join(parent, "obsctl.sock"))

        socket_parent_mode(parent).should eq(0o755)
      end
    end

    # /tmp is owned by root and world-writable, but its sticky bit stops other
    # users deleting our socket, so a socket placed directly there is fine.
    it "accepts a sticky world-writable directory such as /tmp" do
      Obsctl::IPC::SocketPath.ensure_parent(File.join(Dir.tempdir, "obsctl-ensure-parent.sock"))
    end

    it "creates missing intermediate directories" do
      with_socket_parent_tmpdir do |root|
        path = File.join(root, "nested", "deeper", "obsctl", "obsctl.sock")

        Obsctl::IPC::SocketPath.ensure_parent(path)

        Dir.exists?(File.dirname(path)).should be_true
        socket_parent_mode(File.dirname(path)).should eq(0o700)
      end
    end
  end
end
