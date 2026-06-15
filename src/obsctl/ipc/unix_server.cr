require "file_utils"
require "socket"
require "../domain/errors"
require "./client_session"
require "./socket_path"

module Obsctl
  module IPC
    class UnixServer
      alias Handler = Proc(ClientSession, Nil)

      getter socket_path
      @server : UNIXServer?

      def initialize(@socket_path : String = SocketPath.resolve, @codec : Codec = Codec.new)
        @server = nil
        @closed = true
      end

      def listen(handler : Handler) : Nil
        bind
        @closed = false

        until @closed
          begin
            session = accept
            spawn handle(session, handler)
          rescue ex : IO::Error
            raise ex unless @closed
          end
        end
      ensure
        close
      end

      def accept : ClientSession
        server = @server
        raise Domain::IpcConnectionFailed.new("obsctl server socket is not bound") unless server
        ClientSession.new(server.accept, @codec)
      end

      def bind : Nil
        SocketPath.ensure_parent(@socket_path)
        remove_stale_socket
        @server = UNIXServer.new(@socket_path)
        File.chmod(@socket_path, 0o600)
      rescue ex : Socket::BindError
        raise Domain::IpcConnectionFailed.new("obsctl server socket is already active: #{@socket_path}")
      end

      def close : Nil
        @closed = true
        server = @server
        server.close if server && !server.closed?
        File.delete(@socket_path) if File.exists?(@socket_path)
      rescue File::NotFoundError
      end

      private def handle(session : ClientSession, handler : Handler) : Nil
        handler.call(session)
      ensure
        session.try(&.close)
      end

      private def remove_stale_socket : Nil
        return unless File.exists?(@socket_path)

        socket = UNIXSocket.new(@socket_path)
        socket.close
        raise Domain::IpcConnectionFailed.new("obsctl server socket is already active: #{@socket_path}")
      rescue ex : Socket::ConnectError | File::NotFoundError
        File.delete(@socket_path) if File.exists?(@socket_path)
      end
    end
  end
end
