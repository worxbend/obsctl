require "json"
require "../../spec_helper"
require "../../../src/obsctl/cli/completions"

private def completion_snapshot : JSON::Any
  JSON.parse(<<-JSON)
    {
      "scenes": [{"name": "Main Camera"}, {"name": "Break, Please Wait"}],
      "audio_inputs": [{"name": "Mic/Aux"}, {"name": "Desktop Audio"}],
      "profiles": ["Streaming", "Recording"],
      "scene_collections": ["Gaming", "Talk Show"]
    }
    JSON
end

describe Obsctl::CLI::Completions do
  describe ".candidates" do
    it "extracts names for every kind" do
      snapshot = completion_snapshot

      Obsctl::CLI::Completions.candidates("scenes", snapshot).should eq(["Main Camera", "Break, Please Wait"])
      Obsctl::CLI::Completions.candidates("audio", snapshot).should eq(["Mic/Aux", "Desktop Audio"])
      Obsctl::CLI::Completions.candidates("profiles", snapshot).should eq(["Streaming", "Recording"])
      Obsctl::CLI::Completions.candidates("collections", snapshot).should eq(["Gaming", "Talk Show"])
    end

    # Completion runs on every Tab press; an unreachable daemon must not turn
    # into an error in the middle of the user's command line.
    it "yields nothing when the daemon is unreachable" do
      Obsctl::CLI::Completions::CANDIDATE_KINDS.each do |kind|
        Obsctl::CLI::Completions.candidates(kind, nil).should be_empty
      end
    end

    it "tolerates a snapshot missing the requested key" do
      Obsctl::CLI::Completions.candidates("profiles", JSON.parse("{}")).should be_empty
    end

    it "reports an unknown kind even without a daemon" do
      expect_raises(Obsctl::Domain::CommandParseError, /unknown candidate kind/) do
        Obsctl::CLI::Completions.candidates("bogus", nil)
      end
    end
  end

  describe ".render" do
    it "rejects unsupported shells" do
      expect_raises(Obsctl::Domain::CommandParseError, /unknown shell/) do
        Obsctl::CLI::Completions.render("tcsh")
      end
    end

    # The point of generating from the registry is that a new command shows up
    # in every shell without a second edit, so assert the coupling directly.
    it "offers every registry command in every shell" do
      Obsctl::CLI::Completions::SHELLS.each do |shell|
        script = Obsctl::CLI::Completions.render(shell)

        Obsctl::Domain::CommandRegistry.cli_spellings.each do |spelling|
          script.should contain(spelling)
        end
      end
    end

    it "completes record actions and local subcommand words" do
      script = Obsctl::CLI::Completions.render("bash")

      Obsctl::Domain::CommandRegistry::RECORD_ACTIONS.each_key { |action| script.should contain(action) }
      script.should contain("explain diff migrate")
    end

    it "delegates live name lookup back to obsctl rather than parsing JSON in the shell" do
      Obsctl::CLI::Completions::SHELLS.each do |shell|
        script = Obsctl::CLI::Completions.render(shell)

        script.should contain("obsctl completions candidates")
        script.should_not contain("sed -n")
      end
    end
  end
end
