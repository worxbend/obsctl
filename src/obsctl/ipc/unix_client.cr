require "socket"
require "../domain/errors"
require "./client_session"
require "./socket_path"

module Obsctl
  module IPC
    # Local Unix socket IPC client for thin CLI commands.
    class UnixClient
      # Creates a client targeting the resolved obsctl server socket.
      #
      # `timeout` bounds a single request/response exchange; nil waits as long
      # as the daemon needs, which is what long-lived subscriptions require.
      def initialize(
        @socket_path : String = SocketPath.resolve,
        @codec : Codec = Codec.new,
        @timeout : Time::Span? = nil,
      )
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
          session.read_timeout = @timeout
          session.write_message(request)
          message = session.read_message
          response = message.as?(Response)
          raise Domain::IpcProtocolError.new("server closed IPC connection before responding") unless response
          response
        rescue IO::TimeoutError
          raise Domain::RequestTimeout.new(request.command.try(&.name) || request.type)
        ensure
          session.close
        end
      end
    end
  end
end
