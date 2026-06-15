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
    class CommandExecutor
      def initialize(
        @config : Config::Config,
        @config_path : String,
        @state : StateStore,
        @supervisor : ObsSupervisor,
        @client_count : Proc(Int32)? = nil,
      )
      end

      def execute(request : IPC::Request) : IPC::Response
        command = request.command
        raise Domain::IpcProtocolError.new("command request missing command payload") unless command

        result = execute_command(command)
        IPC::Response.new(request.id, true, result)
      rescue ex : Domain::ObsctlError
        IPC::Response.new(request.id, false, nil, IPC::ErrorPayload.new(error_code(ex), ex.message || "request failed"))
      rescue ex
        IPC::Response.new(request.id, false, nil, IPC::ErrorPayload.new("INTERNAL_ERROR", ex.message || "request failed"))
      end

      private def execute_command(command : IPC::CommandPayload) : JSON::Any
        case command.name
        when "ping"
          object({"message" => "pong"})
        when "get_server_status"
          server_status
        when "get_obs_status", "get_snapshot", "status"
          @state.snapshot_json
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
        snapshot = @state.snapshot
        object({
          "pid"           => Process.pid,
          "client_count"  => @client_count.try(&.call) || 0,
          "obs_connected" => snapshot.connected,
          "last_error"    => snapshot.last_error,
        })
      end

      private def required_target(command : IPC::CommandPayload) : String
        command.target || raise Domain::CommandParseError.new("missing command target")
      end

      private def object(values) : JSON::Any
        JSON.parse(values.to_json)
      end

      private def error_code(error : Domain::ObsctlError) : String
        case error
        when Domain::ObsUnavailable
          "OBS_UNAVAILABLE"
        when Domain::SceneNotFound
          "SCENE_NOT_FOUND"
        when Domain::AudioInputNotFound
          "AUDIO_INPUT_NOT_FOUND"
        when Domain::AliasAmbiguous
          "ALIAS_AMBIGUOUS"
        when Domain::CommandParseError
          "COMMAND_PARSE_ERROR"
        when Domain::ConfigInvalid, Domain::ConfigNotFound
          "CONFIG_ERROR"
        else
          "REQUEST_FAILED"
        end
      end
    end
  end
end
