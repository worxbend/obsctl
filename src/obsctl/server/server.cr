require "../config/config"
require "../ipc/command_name"
require "../ipc/protocol"
require "../ipc/state_snapshot_codec"
require "../runtime/logger"
require "./best_effort_log_broadcast"
require "./client_registry"
require "./log_payload"
require "./command_executor"
require "./obs_supervisor"
require "./server_options"
require "./state_store"

module Obsctl
  module Server
    # Foreground local daemon that owns the OBS WebSocket connection and IPC socket.
    class Server
      # How long a freshly accepted connection may stay silent before the
      # daemon drops it. Generous compared to any real client's first write,
      # while still bounding a stalled peer's hold on a file descriptor.
      FIRST_MESSAGE_TIMEOUT = 30.seconds

      # Builds a server runtime around a loaded config and resolved socket path.
      def initialize(
        @config : Config::Config,
        @config_path : String,
        @options : ServerOptions = ServerOptions.new,
        @socket_path : String = IPC::SocketPath.resolve,
        @logger : Runtime::Logger? = nil,
        # Injectable so a spec can prove the drop happens without waiting the
        # production span out.
        @first_message_timeout : Time::Span = FIRST_MESSAGE_TIMEOUT,
      )
        @registry = ClientRegistry.new
        @diagnostic_log_broadcast = BestEffortLogBroadcast.new(->(entry : JSON::Any) { @registry.broadcast("logs", entry) })
        @state = StateStore.new(->(snapshot : OBS::State::ObsSnapshot) { @registry.broadcast("state", IPC::StateSnapshotCodec.encode(snapshot)) })
        event_broadcast = ->(event : JSON::Any) { @registry.broadcast("events", event) }
        log_broadcast = ->(entry : JSON::Any) { broadcast_log(entry) }
        diagnostic_log_broadcast = ->(entry : JSON::Any) { @diagnostic_log_broadcast.broadcast(entry) }
        @supervisor = ObsSupervisor.new(@config, @state, event_broadcast, log_broadcast, @logger, diagnostic_log_broadcast)
        @executor = CommandExecutor.new(
          @config,
          @config_path,
          @state,
          @supervisor,
          @socket_path,
          client_count: -> { @registry.client_count },
          dropped_reconnect_diagnostic_logs: -> { @diagnostic_log_broadcast.dropped_count },
          log_broadcast: log_broadcast
        )
        @ipc = IPC::UnixServer.new(@socket_path)
        @stopped = false
        @stop_lock = Mutex.new
      end

      getter socket_path

      # Starts the OBS supervisor and blocks in the Unix socket accept loop.
      def run : Int32
        log("info", "server_start", "obsctl server starting socket=#{@socket_path}")
        trap_signals
        @supervisor.start
        @ipc.listen(->handle_session(IPC::ClientSession))
        0
      ensure
        stop
      end

      # Stops OBS supervision, closes IPC listeners, and removes the socket.
      #
      # Idempotent: a signal and the `run` ensure block both reach here, and the
      # accept loop unwinds through `ensure` once the listener closes.
      def stop : Nil
        @stop_lock.synchronize do
          return if @stopped
          @stopped = true
        end

        @supervisor.stop
        @ipc.close
        log("info", "server_stop", "obsctl server stopped socket=#{@socket_path}")
      end

      # Converts termination signals into an orderly shutdown.
      #
      # Without this the default disposition kills the process outright: the
      # `run` ensure block never executes, so the OBS WebSocket is dropped
      # without a close frame and the socket file is left on disk for the next
      # start to clean up. `systemctl --user stop` takes exactly this path.
      private def trap_signals : Nil
        {Signal::TERM, Signal::INT}.each do |signal|
          signal.trap do
            log("info", "server_signal", "received #{signal}, shutting down")
            stop
            exit 0
          end
        end
      end

      private def broadcast_log(entry : JSON::Any) : Nil
        @registry.broadcast("logs", entry)
        level = entry["level"]?.try(&.as_s?) || "info"
        code = entry["code"]?.try(&.as_s?) || "server"
        message = entry["message"]?.try(&.as_s?) || ""
        @logger.try(&.write(level, "#{code} #{message}"))
      end

      private def log(level : String, code : String, message : String) : Nil
        broadcast_log(LogPayload.build(level, code, message))
      end

      private def handle_session(session : IPC::ClientSession) : Nil
        # A connection that never sends anything would otherwise keep its fiber
        # and its file descriptor for the life of the daemon. The bound covers
        # the first line only: once a client has identified itself, a `watch`
        # subscriber is expected to sit idle for hours.
        session.read_timeout = @first_message_timeout
        first = true

        while message = session.read_message
          if first
            session.read_timeout = nil
            first = false
          end

          request = message.as?(IPC::Request)
          unless request
            session.write_message(IPC::Response.new("unknown", false, nil, IPC::ErrorPayload.new(IPC::ErrorCode::IPC_PROTOCOL_ERROR, "expected IPC request")))
            next
          end

          if request.subscribe?
            # The acknowledgement and the initial snapshot are written inside
            # the registration so no pushed update can slip in front of them.
            @registry.add(session, request.topics) do
              session.write_message(IPC::Response.new(request.id, true, JSON.parse({"message" => "subscribed"}.to_json)))
              session.write_message(IPC::Event.new("state", IPC::StateSnapshotCodec.encode(@state.snapshot))) if request.topics.includes?("state")
            end
          elsif request.command?
            response = @executor.execute(request)
            session.write_message(response)
            schedule_shutdown if response.ok && request.command.try(&.name) == IPC::CommandName::SHUTDOWN_SERVER
          else
            session.write_message(IPC::Response.new(request.id, false, nil, IPC::ErrorPayload.new(IPC::ErrorCode::IPC_PROTOCOL_ERROR, "unsupported request type")))
          end
        end
      rescue ex : Domain::IpcProtocolError
        session.write_message(IPC::Response.new("unknown", false, nil, IPC::ErrorPayload.new(IPC::ErrorCode::IPC_PROTOCOL_ERROR, ex.message || "invalid IPC request")))
      rescue IO::TimeoutError
        # Nothing to report to a peer that never spoke; just let it go.
      rescue IO::Error
      ensure
        @registry.remove(session)
        session.close
      end

      # How long to let the `shutdown_server` response reach the client before
      # tearing the socket down.
      #
      # The client is still waiting on a reply when the handler decides to stop.
      # Stopping inline would close the listener out from under the write and
      # the client would see a closed connection instead of the acknowledgement
      # it asked for. Yielding to the writing fiber first is what gets the
      # response out; the delay is the margin, not the mechanism.
      SHUTDOWN_RESPONSE_GRACE = 10.milliseconds

      private def schedule_shutdown : Nil
        spawn(name: "obsctl-ipc-shutdown") do
          sleep SHUTDOWN_RESPONSE_GRACE
          stop
        end
      end
    end
  end
end
