require "../../../spec_helper"
require "../../../../src/obsctl/obs/protocol/close_code"

private alias CloseCode = Obsctl::OBS::Protocol::CloseCode

describe Obsctl::OBS::Protocol::CloseCode do
  # Every code obsctl names, listed once so the whole table is covered. Driving
  # this through `Transport` would need one real disconnect per row.
  {
    1000 => "normal closure requested by OBS",
    1001 => "OBS is going away or shutting down",
    1002 => "WebSocket protocol error",
    1005 => "OBS closed without a close status",
    1006 => "connection ended without a close frame",
    1011 => "OBS encountered an internal error",
    1012 => "OBS is restarting",
    1013 => "OBS asked the client to retry later",
    4000 => "OBS reported an unknown reason",
    4001 => "OBS could not decode a client message",
    4002 => "OBS received an unknown message type",
    4003 => "client sent a request before Identify completed",
    4004 => "client attempted to Identify more than once",
    4005 => "OBS authentication failed",
    4006 => "OBS does not support the requested RPC version",
    4007 => "OBS invalidated the session",
    4008 => "OBS does not support a requested feature",
    4009 => "an OBS request was missing its request type",
  }.each do |code, explanation|
    it "explains close code #{code}" do
      CloseCode.explanation(code).should eq(explanation)
    end
  end

  it "falls back to a neutral phrase for a code it does not know" do
    CloseCode.explanation(4999).should eq("peer closed the WebSocket")
  end

  it "falls back for a standard code obsctl does not name" do
    CloseCode.explanation(1003).should eq("peer closed the WebSocket")
  end
end
