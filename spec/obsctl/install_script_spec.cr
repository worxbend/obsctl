require "../spec_helper"

# `install.sh` is a published contract: people pipe it into a shell without
# reading it, and it names release assets the workflow produces. Nothing else
# checks that the two agree, so this does -- the failure mode is a one-liner
# that 404s for every user at once, and it cannot be caught after the fact by
# rerunning a build.
private ROOT             = File.expand_path("../..", __DIR__)
private INSTALL_SCRIPT   = File.join(ROOT, "install.sh")
private RELEASE_WORKFLOW = File.join(ROOT, ".github/workflows/release.yml")
private PAGES_WORKFLOW   = File.join(ROOT, ".github/workflows/pages.yml")

describe "install.sh" do
  it "is valid POSIX shell" do
    status = Process.run("sh", ["-n", INSTALL_SCRIPT], output: :inherit, error: :inherit)
    status.success?.should be_true
  end

  it "is executable" do
    File.info(INSTALL_SCRIPT).permissions.owner_execute?.should be_true
  end

  it "names archives the way the release workflow packages them" do
    script = File.read(INSTALL_SCRIPT)
    workflow = File.read(RELEASE_WORKFLOW)

    # The workflow builds `obsctl-${GITHUB_REF_NAME}-${target}.tar.gz`; the
    # script asks for `obsctl-${version}-${target}.tar.gz`. Same shape, same
    # separators, or the download 404s.
    workflow.should contain(%(ARCHIVE="obsctl-${GITHUB_REF_NAME}-${{ matrix.target }}.tar.gz"))
    script.should contain(%(archive="obsctl-${version}-${target}.tar.gz"))
    script.should contain("SHA256SUMS.txt")
  end

  it "resolves every target the release workflow builds" do
    script = File.read(INSTALL_SCRIPT)
    targets = File.read(RELEASE_WORKFLOW).scan(/target: (linux-[a-z0-9]+)/).map(&.[](1))

    targets.should_not be_empty
    targets.each { |target| script.should contain(target) }
  end

  it "is published where the documented one-liner fetches it" do
    File.read(PAGES_WORKFLOW).should contain("cp install.sh site/install.sh")
    File.read(RELEASE_WORKFLOW).should contain("install.sh")
    File.read(File.join(ROOT, "README.md")).should contain("https://worxbend.github.io/obsctl/install.sh")
  end
end
