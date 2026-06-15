require "../../spec_helper"
require "../../../src/obsctl/config/config"
require "../../../src/obsctl/tui/input/controller"

private def controller
  Obsctl::TUI::Input::Controller.new(
    Obsctl::TUI::Input::Keymap.new(Obsctl::Config::KeymapConfig.new),
    "/"
  )
end

describe Obsctl::TUI::Input::Controller do
  it "opens the command palette and submits an edited command" do
    input = controller

    input.handle("/").kind.should eq(Obsctl::TUI::Input::ActionKind::Render)
    input.command_line.should eq("/")
    input.handle("s")
    input.handle("t")
    input.handle("\u007f")
    input.handle("c")
    input.command_line.should eq("/sc")

    action = input.handle("\r")
    action.kind.should eq(Obsctl::TUI::Input::ActionKind::Submit)
    action.command.should eq("/sc")
    input.command_line.should eq("")
  end

  it "cancels command entry without submitting" do
    input = controller
    input.handle("/")
    input.handle("h")

    action = input.handle("\e")

    action.kind.should eq(Obsctl::TUI::Input::ActionKind::Render)
    input.command_line.should eq("")
  end

  it "maps dashboard shortcuts to commands" do
    input = controller

    reload = input.handle("r")
    dump = input.handle("D")

    reload.kind.should eq(Obsctl::TUI::Input::ActionKind::Submit)
    reload.command.should eq("/reload-config")
    dump.kind.should eq(Obsctl::TUI::Input::ActionKind::Submit)
    dump.command.should eq("/dump-config")
  end

  it "uses q and ctrl-c as dashboard quit keys" do
    input = controller

    input.handle("q").kind.should eq(Obsctl::TUI::Input::ActionKind::Quit)
    input.handle("\u0003").kind.should eq(Obsctl::TUI::Input::ActionKind::Quit)
  end

  it "does not treat q as quit while editing a command" do
    input = controller

    input.handle("/")
    action = input.handle("q")

    action.kind.should eq(Obsctl::TUI::Input::ActionKind::Render)
    input.command_line.should eq("/q")
  end
end
