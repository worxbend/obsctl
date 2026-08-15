require "../ipc/unix_client"

module Obsctl
  module TUI
    class EventSession
      TOPICS = ["state", "events", "logs"]

      def self.connect(socket_path : String) : self
        session = IPC::UnixClient.new(socket_path).connect
        request = IPC::Request.new("tui-subscribe", IPC::Request::TYPE_SUBSCRIBE, topics: TOPICS)
        session.write_message(request)
        response = session.read_message.as?(IPC::Response)
        unless response && response.id == request.id && response.ok
          session.close
          raise Domain::IpcProtocolError.new("server rejected TUI subscription")
        end
        new(session)
      rescue ex : Domain::IpcConnectionFailed
        raise Domain::ServerUnavailable.new(ex.message)
      end

      def initialize(@session : IPC::ClientSession)
      end

      def next_event : IPC::Event?
        loop do
          message = @session.read_message
          return unless message
          if event = message.as?(IPC::Event)
            return event
          end
        end
      end

      def close
        @session.close
      end
    end

    class CommandClient
      # How long a dashboard keypress waits for the daemon to answer.
      #
      # `Dispatcher#command` runs on the same fiber as the render loop, so an
      # unbounded wait here is a frozen dashboard: nothing repaints, no key is
      # processed, and even `q` and Ctrl-C only queue up behind the stuck read.
      # Five seconds is far longer than any local command needs and short
      # enough that the user gets a status-line error instead of a dead
      # terminal. The timeout surfaces as `Domain::RequestTimeout`, which
      # `Dispatcher#command` already renders as an ordinary error message.
      COMMAND_TIMEOUT = 5.seconds

      def initialize(@socket_path : String, @timeout : Time::Span? = COMMAND_TIMEOUT)
        @sequence = 0
        @lock = Mutex.new
      end

      def send(payload : IPC::CommandPayload) : IPC::Response
        id = @lock.synchronize do
          @sequence += 1
          "tui-%06d" % @sequence
        end
        IPC::UnixClient.new(@socket_path, timeout: @timeout).request(IPC::Request.new(id, IPC::Request::TYPE_COMMAND, payload))
      rescue ex : Domain::IpcConnectionFailed
        raise Domain::ServerUnavailable.new(ex.message)
      end
    end
  end
end
