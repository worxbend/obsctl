require "../config/config"
require "../ipc/protocol"
require "../runtime/logger"
require "./best_effort_log_broadcast"
require "./client_registry"
require "./command_executor"
require "./obs_supervisor"
require "./server_options"
require "./state_store"

module Obsctl
  module Server
    # Foreground local daemon that owns the OBS WebSocket connection and IPC socket.
    class Server
      # Builds a server runtime around a loaded config and resolved socket path.
      def initialize(
        @config : Config::Config,
        @config_path : String,
        @options : ServerOptions = ServerOptions.new,
        @socket_path : String = IPC::SocketPath.resolve,
        @logger : Runtime::Logger? = nil,
      )
        @registry = ClientRegistry.new
        @diagnostic_log_broadcast = BestEffortLogBroadcast.new(->(entry : JSON::Any) { @registry.broadcast("logs", entry) })
        @state = StateStore.new(->(snapshot : JSON::Any) { @registry.broadcast("state", snapshot) })
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
      end

      getter socket_path

      # Starts the OBS supervisor and blocks in the Unix socket accept loop.
      def run : Int32
        log("info", "server_start", "obsctl server starting socket=#{@socket_path}")
        @supervisor.start
        @ipc.listen(->handle_session(IPC::ClientSession))
        0
      ensure
        stop
      end

      # Stops OBS supervision, closes IPC listeners, and removes the socket.
      def stop : Nil
        @supervisor.stop
        @ipc.close
        log("info", "server_stop", "obsctl server stopped socket=#{@socket_path}")
      end

      private def broadcast_log(entry : JSON::Any) : Nil
        @registry.broadcast("logs", entry)
        level = entry["level"]?.try(&.as_s?) || "info"
        code = entry["code"]?.try(&.as_s?) || "server"
        message = entry["message"]?.try(&.as_s?) || ""
        @logger.try(&.write(level, "#{code} #{message}"))
      end

      private def log(level : String, code : String, message : String) : Nil
        broadcast_log(JSON.parse({
          level:      level,
          code:       code,
          message:    message,
          created_at: Time.utc.to_rfc3339,
        }.to_json))
      end

      private def handle_session(session : IPC::ClientSession) : Nil
        while message = session.read_message
          request = message.as?(IPC::Request)
          unless request
            session.write_message(IPC::Response.new("unknown", false, nil, IPC::ErrorPayload.new(IPC::ErrorCode::IPC_PROTOCOL_ERROR, "expected IPC request")))
            next
          end

          if request.subscribe?
            @registry.add(session, request.topics)
            session.write_message(IPC::Response.new(request.id, true, JSON.parse({"message" => "subscribed"}.to_json)))
            session.write_message(IPC::Event.new("state", @state.snapshot_json)) if request.topics.includes?("state")
          elsif request.command?
            response = @executor.execute(request)
            session.write_message(response)
            schedule_shutdown if response.ok && request.command.try(&.name) == "shutdown_server"
          else
            session.write_message(IPC::Response.new(request.id, false, nil, IPC::ErrorPayload.new(IPC::ErrorCode::IPC_PROTOCOL_ERROR, "unsupported request type")))
          end
        end
      rescue ex : Domain::IpcProtocolError
        session.write_message(IPC::Response.new("unknown", false, nil, IPC::ErrorPayload.new(IPC::ErrorCode::IPC_PROTOCOL_ERROR, ex.message || "invalid IPC request")))
      rescue IO::Error
      ensure
        @registry.remove(session)
        session.close
      end

      private def schedule_shutdown : Nil
        spawn(name: "obsctl-ipc-shutdown") do
          sleep 10.milliseconds
          stop
        end
      end
    end
  end
end
