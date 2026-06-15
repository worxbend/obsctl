require "socket"
require "./codec"

module Obsctl
  module IPC
    class ClientSession
      getter socket

      def initialize(@socket : UNIXSocket, @codec : Codec = Codec.new)
        @write_lock = Mutex.new
      end

      def read_message : Message?
        line = socket.gets
        return nil unless line
        @codec.decode(line)
      end

      def write_message(message : Message) : Nil
        @write_lock.synchronize do
          socket << @codec.encode(message)
          socket.flush
        end
      end

      def close : Nil
        socket.close unless socket.closed?
      end
    end
  end
end
