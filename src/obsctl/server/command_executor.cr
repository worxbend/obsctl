require "json"
require "../config/config"
require "../config/config_dump"
require "../config/config_loader"
require "../config/config_writer"
require "../domain/aliases"
require "../domain/errors"
require "../ipc/request"
require "../ipc/response"
require "./obs_supervisor"
require "./state_store"

module Obsctl
  module Server
    # Executes validated IPC commands against server-owned config, state, and OBS client.
    class CommandExecutor
      # Creates a command executor for one server runtime.
      def initialize(
        @config : Config::Config,
        @config_path : String,
        @state : StateStore,
        @supervisor : ObsSupervisor,
        @socket_path : String,
        @started_at : Time = Time.utc,
        @client_count : Proc(Int32)? = nil,
        @dropped_reconnect_diagnostic_logs : Proc(UInt64)? = nil,
        @log_broadcast : Proc(JSON::Any, Nil)? = nil,
      )
      end

      # Executes a command request and converts domain failures into IPC errors.
      def execute(request : IPC::Request) : IPC::Response
        command = request.command
        raise Domain::IpcProtocolError.new("command request missing command payload") unless command

        result = execute_command(command)
        IPC::Response.new(request.id, true, result)
      rescue ex : Domain::ObsctlError
        publish_log("warn", "command_failed", IPC::ErrorPayload.sanitize_message(ex.message || "request failed"))
        IPC::Response.new(request.id, false, nil, IPC::ErrorPayload.from_exception(ex))
      rescue ex
        publish_log("error", "command_failed", IPC::ErrorPayload.sanitize_message(ex.message || "request failed"))
        IPC::Response.new(request.id, false, nil, IPC::ErrorPayload.server_error)
      end

      private def execute_command(command : IPC::CommandPayload) : JSON::Any
        case command.name
        when "ping"
          object({"message" => "pong"})
        when "get_server_status"
          server_status
        when "status"
          combined_status
        when "get_obs_status", "get_snapshot"
          @state.snapshot_json
        when "validate_config"
          Config::ConfigLoader.new.load(@config_path)
          object({"message" => "config valid: #{@config_path}"})
        when "reconnect_obs"
          unless @supervisor.alive? && @supervisor.reconnect
            raise Domain::ObsUnavailable.new("OBS supervisor is not running; restart the server or enable reconnect.")
          end
          object({"message" => "OBS reconnect requested"})
        when "shutdown_server"
          unless @config.server.allow_remote_shutdown
            raise Domain::CommandParseError.new("remote shutdown is disabled")
          end
          object({"message" => "server shutdown requested"})
        when "set_scene"
          target = required_target(command)
          scene = Domain::Aliases.resolve_scene(@config, target)
          @supervisor.with_client(&.set_scene(scene.name))
          refresh_snapshot
          object({"message" => "scene set: #{scene.name}"})
        when "mute"
          set_mute(command, true)
        when "unmute"
          set_mute(command, false)
        when "toggle_mute"
          input = Domain::Aliases.resolve_audio(@config, required_target(command))
          @supervisor.with_client(&.toggle_mute(input.name))
          refresh_snapshot
          object({"message" => "toggled mute: #{input.name}"})
        when "set_volume"
          input = Domain::Aliases.resolve_audio(@config, required_target(command))
          percent = command.percent
          raise Domain::CommandParseError.new("missing volume percent") unless percent
          @supervisor.with_client(&.set_volume(input.name, percent))
          refresh_snapshot
          object({"message" => "volume set: #{input.name} #{percent}%"})
        when "dump_config"
          @supervisor.with_client do |client|
            merged = Config::ConfigDump.merge(@config, client.scene_names, client.input_names)
            Config::ConfigWriter.new.write(@config_path, merged, backup: true)
            @config = merged
          end
          refresh_snapshot
          object({"message" => "config dumped: #{@config_path}"})
        when "reload_config"
          @config = Config::ConfigLoader.new.load(@config_path)
          refresh_snapshot
          object({"message" => "config reloaded: #{@config_path}"})
        else
          raise Domain::CommandParseError.new("unsupported IPC command: #{command.name}")
        end
      end

      private def set_mute(command : IPC::CommandPayload, muted : Bool) : JSON::Any
        input = Domain::Aliases.resolve_audio(@config, required_target(command))
        @supervisor.with_client { |client| client.mute(input.name, muted) }
        refresh_snapshot
        object({"message" => "#{muted ? "muted" : "unmuted"}: #{input.name}"})
      end

      private def refresh_snapshot : Nil
        @supervisor.with_client { |client| @state.update(client.snapshot) }
      rescue Domain::ObsctlError
      end

      private def server_status : JSON::Any
        server_status_for(@state.snapshot)
      end

      private def combined_status : JSON::Any
        snapshot = @state.snapshot
        object({
          "server" => server_status_for(snapshot),
          "obs"    => StateStore.snapshot_to_json(snapshot),
        })
      end

      private def server_status_for(snapshot : OBS::State::ObsSnapshot) : JSON::Any
        telemetry = @state.telemetry
        object({
          "pid"                               => Process.pid,
          "uptime_seconds"                    => (Time.utc - @started_at).total_seconds.to_i64,
          "socket_path"                       => @socket_path,
          "client_count"                      => @client_count.try(&.call) || 0,
          "dropped_reconnect_diagnostic_logs" => @dropped_reconnect_diagnostic_logs.try(&.call) || 0_u64,
          "obs_connected"                     => snapshot.connected,
          "reconnecting"                      => telemetry.reconnecting,
          "last_connected_at"                 => timestamp(telemetry.last_connected_at),
          "last_disconnected_at"              => timestamp(telemetry.last_disconnected_at),
          "last_reconnect_attempt_at"         => timestamp(telemetry.last_reconnect_attempt_at),
          "last_connection_failed_at"         => timestamp(telemetry.last_connection_failed_at),
          "last_error"                        => snapshot.last_error,
        })
      end

      private def timestamp(value : Time?) : String?
        value.try(&.to_rfc3339)
      end

      private def required_target(command : IPC::CommandPayload) : String
        command.target || raise Domain::CommandParseError.new("missing command target")
      end

      private def object(values) : JSON::Any
        JSON.parse(values.to_json)
      end

      private def publish_log(level : String, code : String, message : String) : Nil
        @log_broadcast.try(&.call(JSON.parse({
          level:      level,
          code:       code,
          message:    message,
          created_at: Time.utc.to_rfc3339,
        }.to_json)))
      end
    end
  end
end
