require "../config/config"
require "../ipc/protocol"
require "./command_executor"
require "./obs_supervisor"
require "./server_options"
require "./state_store"

module Obsctl
  module Server
    class Server
      def initialize(
        @config : Config::Config,
        @config_path : String,
        @options : ServerOptions = ServerOptions.new,
        @socket_path : String = IPC::SocketPath.resolve,
      )
        @state = StateStore.new
        @supervisor = ObsSupervisor.new(@config, @state)
        @executor = CommandExecutor.new(@config, @config_path, @state, @supervisor)
        @ipc = IPC::UnixServer.new(@socket_path)
      end

      getter socket_path

      def run : Int32
        @supervisor.start
        @ipc.listen(->handle_session(IPC::ClientSession))
        0
      ensure
        stop
      end

      def stop : Nil
        @supervisor.stop
        @ipc.close
      end

      private def handle_session(session : IPC::ClientSession) : Nil
        while message = session.read_message
          request = message.as?(IPC::Request)
          unless request
            session.write_message(IPC::Response.new("unknown", false, nil, IPC::ErrorPayload.new("INVALID_REQUEST", "expected IPC request")))
            next
          end

          if request.subscribe?
            session.write_message(IPC::Response.new(request.id, true, JSON.parse({"message" => "subscribed"}.to_json)))
            session.write_message(IPC::Event.new("state", @state.snapshot_json))
          elsif request.command?
            session.write_message(@executor.execute(request))
          else
            session.write_message(IPC::Response.new(request.id, false, nil, IPC::ErrorPayload.new("INVALID_REQUEST", "unsupported request type")))
          end
        end
      end
    end
  end
end
