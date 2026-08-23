require "../spec_helper"
require "../../src/crytui"

describe CryTUI::TerminalSize do
  it "uses validated COLUMNS and LINES as a non-TTY fallback" do
    previous_columns = ENV["COLUMNS"]?
    previous_lines = ENV["LINES"]?
    ENV["COLUMNS"] = "132"
    ENV["LINES"] = "43"
    CryTUI::TerminalSize.from_environment.should eq(CryTUI::Rect.new(0, 0, 132, 43))
  ensure
    if previous_columns
      ENV["COLUMNS"] = previous_columns
    else
      ENV.delete("COLUMNS")
    end
    if previous_lines
      ENV["LINES"] = previous_lines
    else
      ENV.delete("LINES")
    end
  end

  it "rejects missing, nonnumeric, and nonpositive fallback dimensions" do
    previous_columns = ENV["COLUMNS"]?
    previous_lines = ENV["LINES"]?
    ENV["COLUMNS"] = "nope"
    ENV["LINES"] = "0"
    CryTUI::TerminalSize.from_environment.should be_nil
  ensure
    if previous_columns
      ENV["COLUMNS"] = previous_columns
    else
      ENV.delete("COLUMNS")
    end
    if previous_lines
      ENV["LINES"] = previous_lines
    else
      ENV.delete("LINES")
    end
  end
end
