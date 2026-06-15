require "socket"
require "../domain/errors"
require "./client_session"
require "./socket_path"

module Obsctl
  module IPC
    # Local Unix socket IPC client for thin CLI and TUI commands.
    class UnixClient
      # Creates a client targeting the resolved obsctl server socket.
      def initialize(@socket_path : String = SocketPath.resolve, @codec : Codec = Codec.new)
      end

      # Opens a persistent client session to the local server.
      def connect : ClientSession
        ClientSession.new(UNIXSocket.new(@socket_path), @codec)
      rescue ex : File::NotFoundError | Socket::ConnectError
        raise Domain::IpcConnectionFailed.new("obsctl server is not running at #{@socket_path}")
      end

      # Sends one request and waits for its correlated response.
      def request(request : Request) : Response
        session = connect
        begin
          session.write_message(request)
          message = session.read_message
          response = message.as?(Response)
          raise Domain::IpcProtocolError.new("server closed IPC connection before responding") unless response
          response
        ensure
          session.close
        end
      end
    end
  end
end
