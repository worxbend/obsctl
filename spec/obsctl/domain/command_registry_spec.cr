require "../../spec_helper"
require "../../../src/obsctl/domain/command_registry"
require "../../../src/obsctl/domain/command_parser"
require "../../../src/obsctl/tui/completion"
require "../../../src/obsctl/cli/main"

# The registry exists so the command set cannot differ between the parser, the
# `--json` allowlist, palette completion, help, and the generated shell
# completions. These examples assert that coupling rather than restating the
# command list, so adding a command to the registry is the only edit needed.
describe Obsctl::Domain::CommandRegistry do
  it "resolves every spelling, with or without the palette prefix" do
    Obsctl::Domain::CommandRegistry::SPECS.each do |spec|
      spec.spellings.each do |spelling|
        Obsctl::Domain::CommandRegistry[spelling]?.should eq(spec)
        Obsctl::Domain::CommandRegistry["/#{spelling}"]?.should eq(spec)
        Obsctl::Domain::CommandRegistry[spelling.upcase]?.should eq(spec)
      end
    end
  end

  it "gives every spelling a unique owner" do
    spellings = Obsctl::Domain::CommandRegistry::SPECS.flat_map(&.spellings)

    spellings.size.should eq(spellings.uniq.size)
  end

  it "parses every spelling it advertises" do
    parser = Obsctl::Domain::CommandParser.new

    Obsctl::Domain::CommandRegistry::SPECS.each do |spec|
      args = spec.arguments.first(spec.required_arguments).map do |kind|
        kind.percent? ? "50" : "placeholder"
      end

      spec.spellings.each do |spelling|
        parser.parse([spelling] + args).should be_a(Obsctl::Domain::Command)
      end
    end
  end

  it "gives every daemon-bound command an IPC name" do
    parser = Obsctl::Domain::CommandParser.new

    Obsctl::Domain::CommandRegistry.for_surface(Obsctl::Domain::CommandSurface::Cli).each do |spec|
      args = spec.arguments.first(spec.required_arguments).map do |kind|
        kind.percent? ? "50" : "placeholder"
      end

      parser.parse([spec.name] + args).ipc_name.should_not be_nil
    end
  end

  # The drift this replaces: `set-scene` used to parse but be rejected by
  # `--json`, because the allowlist was maintained by hand.
  it "supports --json for every spelling of a JSON-capable command" do
    Obsctl::Domain::CommandRegistry::SPECS.select(&.json?).each do |spec|
      spec.spellings.each do |spelling|
        Obsctl::Domain::CommandRegistry.json?(spelling).should be_true
      end
    end
  end

  it "offers every palette command in completion" do
    Obsctl::Domain::CommandRegistry.for_surface(Obsctl::Domain::CommandSurface::Palette).each do |spec|
      Obsctl::TUI::Completion::ALL_COMMANDS.should contain("/#{spec.name}")
    end
  end

  it "documents every CLI command in --help" do
    stdout = IO::Memory.new
    Obsctl::CLI::Main.run(["--help"], nil, stdout, IO::Memory.new).should eq(0)
    help = stdout.to_s

    Obsctl::Domain::CommandRegistry.cli_names.each { |name| help.should contain(name) }
  end

  describe "usage" do
    it "renders argument placeholders" do
      Obsctl::Domain::CommandRegistry["vol"]?.not_nil!.usage.should eq("vol <audio-input> <0-100>")
      Obsctl::Domain::CommandRegistry["status"]?.not_nil!.usage.should eq("status")
    end

    it "names the command and its usage when the arity is wrong" do
      spec = Obsctl::Domain::CommandRegistry["scene"]?.not_nil!

      expect_raises(Obsctl::Domain::CommandParseError, /wrong argument count for scene; usage: scene <scene>/) do
        spec.validate_arity!([] of String)
      end
    end

    it "accepts an optional argument being omitted" do
      spec = Obsctl::Domain::CommandRegistry["rec"]?.not_nil!

      spec.validate_arity!([] of String)
      spec.validate_arity!(["start"])
      expect_raises(Obsctl::Domain::CommandParseError) { spec.validate_arity!(["start", "extra"]) }
    end
  end
end
