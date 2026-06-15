require "socket"
require "../domain/errors"
require "./client_session"
require "./socket_path"

module Obsctl
  module IPC
    class UnixClient
      def initialize(@socket_path : String = SocketPath.resolve, @codec : Codec = Codec.new)
      end

      def connect : ClientSession
        ClientSession.new(UNIXSocket.new(@socket_path), @codec)
      rescue ex : File::NotFoundError | Socket::ConnectError
        raise Domain::IpcConnectionFailed.new("obsctl server is not running at #{@socket_path}")
      end

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
