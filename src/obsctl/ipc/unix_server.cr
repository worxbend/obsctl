require "file_utils"
require "socket"
require "../domain/errors"
require "./client_session"
require "./socket_path"

lib LibC
  # Crystal's standard library has no `umask` wrapper, and the socket has to be
  # created with the right mode rather than corrected afterwards.
  fun umask(mask : ModeT) : ModeT
end

module Obsctl
  module IPC
    # Unix domain socket server for the local obsctl daemon IPC endpoint.
    class UnixServer
      # Masks off every group and other permission bit, so anything created
      # while it is installed is owner-only.
      OWNER_ONLY_UMASK = 0o177_u32
      alias Handler = Proc(ClientSession, Nil)

      getter socket_path
      @server : UNIXServer?

      # Creates a server that will bind the configured socket path on listen.
      def initialize(@socket_path : String = SocketPath.resolve, @codec : Codec = Codec.new)
        @server = nil
        @closed = true
      end

      # Binds the socket and handles accepted sessions until closed.
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

      # Accepts one client session from the bound server socket.
      def accept : ClientSession
        server = @server
        raise Domain::IpcConnectionFailed.new("obsctl server socket is not bound") unless server
        ClientSession.new(server.accept, @codec)
      end

      # Creates the socket, removing stale socket files when no server responds.
      #
      # The umask is narrowed around the bind rather than the socket being
      # chmod'ed afterwards. Creating it first and fixing the mode second leaves
      # a window — short, but real — where the socket exists at whatever the
      # process umask allows, typically group- and world-readable. The parent
      # directory is 0700 (see `SocketPath.ensure_parent`), so nothing could
      # reach through that window in practice; closing it anyway means the
      # socket's own permissions are correct from the moment it exists, and the
      # daemon is not relying on two separate defences to get one thing right.
      def bind : Nil
        SocketPath.ensure_parent(@socket_path)
        remove_stale_socket
        previous_umask = LibC.umask(OWNER_ONLY_UMASK)
        begin
          @server = UNIXServer.new(@socket_path)
        ensure
          LibC.umask(previous_umask)
        end
        # Belt and braces: the umask above is what makes the mode right at
        # creation time, and this makes it right even on a platform whose
        # socket creation ignores the umask.
        File.chmod(@socket_path, 0o600)
      rescue Socket::BindError
        raise Domain::IpcConnectionFailed.new("obsctl server socket is already active: #{@socket_path}")
      end

      # Closes the server socket and removes the socket path.
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
      rescue Socket::ConnectError | File::NotFoundError
        File.delete(@socket_path) if File.exists?(@socket_path)
      end
    end
  end
end
