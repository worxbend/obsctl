require "socket"
require "./codec"

module Obsctl
  module IPC
    # Thread-safe message wrapper around one connected Unix socket.
    class ClientSession
      getter socket

      # Creates a session over an accepted or connected Unix socket.
      def initialize(@socket : UNIXSocket, @codec : Codec = Codec.new)
        @write_lock = Mutex.new
      end

      # Reads and decodes one message, returning nil when the peer closes.
      def read_message : Message?
        line = socket.gets
        return nil unless line
        @codec.decode(line)
      end

      # Encodes and writes one message without interleaving concurrent writers.
      def write_message(message : Message) : Nil
        @write_lock.synchronize do
          socket << @codec.encode(message)
          socket.flush
        end
      end

      # Closes the underlying socket if it is still open.
      def close : Nil
        socket.close unless socket.closed?
      end
    end
  end
end
