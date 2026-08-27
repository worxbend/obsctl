require "../../spec_helper"
require "../../../src/obsctl/domain/scene_profiles"

private BASELINE = [
  {"Main", false},
  {"Utility BG", true},
  {"Overlay Src", false},
]

private def resolve(active : Array(String)? = nil)
  Obsctl::Domain::SceneVisibility.resolve(BASELINE, active)
end

describe Obsctl::Domain::SceneVisibility do
  it "lets the per-scene flags decide when no profile is active" do
    visibility = resolve

    visibility.hidden?("Utility BG").should be_true
    visibility.hidden?("Main").should be_false
    visibility.hidden_count.should eq(1)
  end

  it "replaces the baseline when a profile is active, in both directions" do
    # The whole point of the rule: a profile can reveal a scene the config
    # marks hidden, and hide one the config marks visible.
    visibility = resolve(["Overlay Src"])

    visibility.hidden?("Overlay Src").should be_true
    visibility.hidden?("Utility BG").should be_false
    visibility.hidden_count.should eq(1)
  end

  it "hides nothing for a profile that names nothing" do
    # An empty list is not the same as no profile: it is how "show every scene"
    # is expressed, and it has to beat the per-scene flags to mean that.
    visibility = resolve([] of String)

    visibility.hidden?("Utility BG").should be_false
    visibility.hidden_count.should eq(0)
  end

  it "matches regardless of case and surrounding whitespace, on both sides" do
    visibility = resolve(["  utility bg  "])

    visibility.hidden?("Utility BG").should be_true
    visibility.hidden?(" UTILITY BG ").should be_true
  end

  it "drops an unusable name rather than letting it hide everything" do
    visibility = resolve(["bad\nname", "Utility BG"])

    visibility.hidden_count.should eq(1)
    visibility.hidden?("Utility BG").should be_true
    visibility.hidden?("bad\nname").should be_false
  end

  it "counts a scene named twice once" do
    resolve(["Utility BG", "utility bg"]).hidden_count.should eq(1)
  end

  it "folds ASCII case only, so two scenes OBS tells apart do not collide" do
    # Crystal's Unicode-aware downcase would fold "İ" to "i̇" and make these
    # one name; obsctl-rs folds ASCII only, and the daemon has to agree with it.
    visibility = Obsctl::Domain::SceneVisibility.resolve([] of Tuple(String, Bool), ["İntro"])

    visibility.hidden?("İntro").should be_true
    visibility.hidden?("intro").should be_false
  end

  it "compares by the resolved set, not by how it was built" do
    resolve(["Utility BG"]).should eq(resolve(["  utility bg  "]))
  end
end

describe Obsctl::Domain::SceneProfileNames do
  it "trims but keeps case, because OBS is told the name as written" do
    Obsctl::Domain::SceneProfileNames.checked_name("  Main Camera ").should eq("Main Camera")
  end

  it "folds case for matching" do
    Obsctl::Domain::SceneProfileNames.normalized_name("  Main Camera ").should eq("main camera")
  end

  it "rejects blank, control-bearing and oversize names with the reason" do
    names = Obsctl::Domain::SceneProfileNames
    names.checked_name_error("   ").should eq("must not be blank")
    # In the middle, where trimming would not have saved it.
    names.checked_name_error("main\tcam").should eq("must not contain control characters")
    names.checked_name_error("a" * 257).should eq("must not be longer than 256 characters")
    names.checked_name_error("a" * 256).should be_nil
  end

  it "rejects a control character that trimming would otherwise remove" do
    # The check runs before the trim on purpose: a name carrying a tab is
    # unusable wherever the tab sits.
    Obsctl::Domain::SceneProfileNames.checked_name("\tMain").should be_nil
  end

  it "accepts spaces, punctuation and non-ASCII, which are not the rule here" do
    Obsctl::Domain::SceneProfileNames.checked_name("Scène 4 (interim) 🎥").should eq("Scène 4 (interim) 🎥")
  end
end
