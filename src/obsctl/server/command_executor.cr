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
      JSON_SAFE_COUNTER_MAX = Int64::MAX.to_u64

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

      # Routes an IPC command to the group that owns it.
      #
      # The groups return nil for a name they do not handle, so an unknown
      # command falls through to a single parse error at the bottom.
      private def execute_command(command : IPC::CommandPayload) : JSON::Any
        status_command(command) ||
          studio_command(command) ||
          audio_command(command) ||
          output_command(command) ||
          config_command(command) ||
          raise Domain::CommandParseError.new("unsupported IPC command: #{command.name}")
      end

      private def status_command(command : IPC::CommandPayload) : JSON::Any?
        case command.name
        when "ping"                           then object({"message" => "pong"})
        when "get_server_status"              then server_status
        when "status"                         then combined_status
        when "get_obs_status", "get_snapshot" then @state.snapshot_json
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
        end
      end

      private def studio_command(command : IPC::CommandPayload) : JSON::Any?
        case command.name
        when "set_scene"
          target = required_target(command)
          live_names = @state.snapshot.scenes.map(&.name)
          scene = Domain::Aliases.resolve_scene(@config, target, live_names)
          @supervisor.with_client(&.set_scene(scene.name))
          refresh_snapshot
          object({"message" => "scene set: #{scene.name}"})
        when "set_profile"
          target = required_target(command)
          @supervisor.with_client(&.set_profile(target))
          refresh_snapshot
          object({"message" => "profile set: #{target}"})
        when "set_scene_collection"
          target = required_target(command)
          @supervisor.with_client(&.set_scene_collection(target))
          refresh_snapshot
          object({"message" => "scene collection set: #{target}"})
        end
      end

      private def audio_command(command : IPC::CommandPayload) : JSON::Any?
        case command.name
        when "mute"   then set_mute(command, true)
        when "unmute" then set_mute(command, false)
        when "toggle_mute"
          input = resolve_audio(required_target(command))
          @supervisor.with_client(&.toggle_mute(input.name))
          refresh_snapshot
          object({"message" => "toggled mute: #{input.name}"})
        when "set_volume"
          input = resolve_audio(required_target(command))
          percent = command.percent
          raise Domain::CommandParseError.new("missing volume percent") unless percent
          @supervisor.with_client(&.set_volume(input.name, percent))
          @state.update_input_volume(input.name, Domain::Aliases.volume_percent_to_mul(percent), nil)
          object({"message" => "volume set: #{input.name} #{percent}%"})
        end
      end

      private def output_command(command : IPC::CommandPayload) : JSON::Any?
        case command.name
        when "toggle_stream"
          active = @supervisor.with_client(&.toggle_stream)
          refresh_snapshot
          object({"message" => "streaming #{output_state(active)}"})
        when "toggle_record"
          active = @supervisor.with_client(&.toggle_record)
          refresh_snapshot
          object({"message" => "recording #{output_state(active)}"})
        when "start_record"
          @supervisor.with_client(&.start_record)
          refresh_snapshot
          object({"message" => "recording started"})
        when "stop_record"
          output_path = @supervisor.with_client(&.stop_record)
          refresh_snapshot
          message = output_path ? "recording stopped: #{output_path}" : "recording stopped"
          object({"message" => message})
        when "pause_record"
          @supervisor.with_client(&.pause_record)
          refresh_snapshot
          object({"message" => "recording paused"})
        when "resume_record"
          @supervisor.with_client(&.resume_record)
          refresh_snapshot
          object({"message" => "recording resumed"})
        when "record_status"
          record_status_payload(@supervisor.with_client(&.record_status))
        end
      end

      private def config_command(command : IPC::CommandPayload) : JSON::Any?
        case command.name
        when "validate_config"
          Config::ConfigLoader.new.load(@config_path)
          object({"message" => "config valid: #{@config_path}"})
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
        end
      end

      private def set_mute(command : IPC::CommandPayload, muted : Bool) : JSON::Any
        input = resolve_audio(required_target(command))
        @supervisor.with_client(&.mute(input.name, muted))
        refresh_snapshot
        object({"message" => "#{muted ? "muted" : "unmuted"}: #{input.name}"})
      end

      private def resolve_audio(target : String) : Config::AudioInputConfig
        live_names = @state.snapshot.audio_inputs.map(&.name)
        Domain::Aliases.resolve_audio(@config, target, live_names)
      end

      private def refresh_snapshot : Nil
        @supervisor.with_client { |client| @state.update(client.snapshot) }
      rescue Domain::ObsctlError
      end

      private def output_state(active : Bool?) : String
        active.nil? ? "toggled" : (active ? "started" : "stopped")
      end

      # Carries the structured record fields plus a one-line `message`, so the
      # TUI and any generic consumer can render it the same way as every other
      # command result without special-casing.
      private def record_status_payload(status : OBS::State::RecordStatus) : JSON::Any
        object({
          "message"     => "recording #{record_state_label(status)}",
          "active"      => status.active,
          "paused"      => status.paused,
          "timecode"    => status.timecode,
          "duration_ms" => status.duration_ms,
          "bytes"       => status.bytes,
        })
      end

      private def record_state_label(status : OBS::State::RecordStatus) : String
        case status.active
        when true  then status.paused == true ? "paused" : "active"
        when false then "stopped"
        else            "state unknown"
        end
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
          "dropped_reconnect_diagnostic_logs" => dropped_reconnect_diagnostic_logs,
          "obs_connected"                     => snapshot.connected,
          "reconnecting"                      => telemetry.reconnecting,
          "last_connected_at"                 => timestamp(telemetry.last_connected_at),
          "last_disconnected_at"              => timestamp(telemetry.last_disconnected_at),
          "last_reconnect_attempt_at"         => timestamp(telemetry.last_reconnect_attempt_at),
          "last_connection_failed_at"         => timestamp(telemetry.last_connection_failed_at),
          "last_error"                        => snapshot.last_error,
        })
      end

      private def dropped_reconnect_diagnostic_logs : Int64
        value = @dropped_reconnect_diagnostic_logs.try(&.call) || 0_u64
        return Int64::MAX if value > JSON_SAFE_COUNTER_MAX

        value.to_i64
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
