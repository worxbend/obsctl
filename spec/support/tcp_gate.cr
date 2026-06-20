require "socket"

module Obsctl
  module SpecSupport
    # Reserves a TCP port by binding a TCPSocket without calling listen. Incoming
    # connection attempts get ECONNREFUSED immediately (no listen backlog),
    # which matches the OBS-unavailable scenario without hanging the supervisor
    # on a WebSocket handshake timeout. When the test is ready for OBS to
    # become reachable, call open_fake_obs: it releases the bound socket and
    # immediately starts FakeObsServer on the same port. The window between
    # release and bind is a few CPU instructions, eliminating the TOCTOU race
    # in the old unused_tcp_port pattern.
    class TcpGate
      getter port : Int32

      def initialize
        @socket = TCPSocket.new
        @socket.reuse_address = true
        @socket.bind("127.0.0.1", 0)
        @port = @socket.local_address.port
        @released = false
        @mutex = Mutex.new
      end

      # Close the reservation socket so the port becomes available for binding.
      # Safe to call multiple times.
      def release : Nil
        @mutex.synchronize do
          return if @released
          @released = true
        end
        @socket.close rescue nil
      end

      # Release the reservation and immediately start a FakeObsServer on the
      # same port.
      def open_fake_obs : FakeObsServer
        release
        FakeObsServer.new(port: @port).start
      end
    end
  end
end
