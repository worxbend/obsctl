require "./model"
require "./event_applier"
require "./session_client"
require "../config/config_loader"
require "../domain/command"
require "../domain/command_parser"
require "../domain/command_result"
require "../domain/errors"
require "../ipc/socket_path"
require "../runtime/reconnect_policy"

module Obsctl
  module TUI
    record SessionResult, model : Model, quit : Bool = false

    class Session
      getter config

      def initialize(
        @config : Config::Config,
        @config_path : String,
        @client_factory : Proc(Config::Config, SessionClient) = ->(config : Config::Config) {
          IpcSessionClient.new(IPC::UnixClient.new(IPC::SocketPath.resolve(config.server.socket_path))).as(SessionClient)
        },
      )
        @parser = Domain::CommandParser.new
        @snapshot = nil.as(OBS::State::ObsSnapshot?)
        @client = nil.as(SessionClient?)
        @last_result = nil.as(String?)
        @reconnect_attempt = 0
        @next_reconnect_at = nil.as(Time?)
      end

      def start : Model
        connect_with_current_config("Enter command, /quit to exit.")
      end

      def execute_line(line : String) : SessionResult
        drain_events
        command = @parser.parse(line)
        execute(command)
      rescue ex : Domain::ObsctlError
        SessionResult.new(model_with_result(ex.message || "command failed"))
      end

      def poll_events : Model
        changed = drain_events
        return model_with_result("state updated") if changed
        return reconnect_if_due if reconnect_due?

        model_with_result(@last_result)
      end

      def execute(command : Domain::Command) : SessionResult
        case command
        when Domain::QuitCommand
          close
          SessionResult.new(model_with_result("quit"), quit: true)
        when Domain::HelpCommand
          SessionResult.new(model_with_result(help_text))
        when Domain::StatusCommand
          SessionResult.new(refresh_after_success("status refreshed"))
        when Domain::ObsStatusCommand
          SessionResult.new(refresh_after_success("OBS status refreshed"))
        when Domain::ValidateConfigCommand
          validate_config
        when Domain::ReconnectCommand
          reconnect_obs
        when Domain::ReloadConfigCommand
          reload_config
        when Domain::DumpConfigCommand
          dump_config
        when Domain::ConnectCommand
          SessionResult.new(connect_with_current_config("connected"))
        when Domain::DisconnectCommand
          close
          @snapshot = disconnected_snapshot(nil)
          SessionResult.new(model_with_result("disconnected"))
        when Domain::SetSceneCommand
          connected_client.set_scene(command.target)
          SessionResult.new(refresh_after_success("scene set: #{command.target}"))
        when Domain::MuteCommand
          connected_client.mute(command.target, true)
          SessionResult.new(refresh_after_success("muted: #{command.target}"))
        when Domain::UnmuteCommand
          connected_client.mute(command.target, false)
          SessionResult.new(refresh_after_success("unmuted: #{command.target}"))
        when Domain::ToggleMuteCommand
          connected_client.toggle_mute(command.target)
          SessionResult.new(refresh_after_success("toggled mute: #{command.target}"))
        when Domain::VolumeCommand
          connected_client.set_volume(command.target, command.percent)
          SessionResult.new(refresh_after_success("volume set: #{command.target} #{command.percent}%"))
        else
          SessionResult.new(model_with_result("unsupported command"))
        end
      rescue ex : Domain::ObsctlError
        SessionResult.new(model_with_result(ex.message || "command failed"))
      end

      def close : Nil
        @client.try(&.close)
      rescue
      ensure
        @client = nil
      end

      private def reload_config : SessionResult
        connected_client.reload_config
        @config = Config::ConfigLoader.new.load(@config_path) if File.exists?(@config_path)
        SessionResult.new(refresh_after_success("config reloaded: #{@config_path}"))
      end

      private def dump_config : SessionResult
        connected_client.dump_config
        @config = Config::ConfigLoader.new.load(@config_path) if File.exists?(@config_path)
        SessionResult.new(refresh_after_success("config dumped: #{@config_path}"))
      end

      private def validate_config : SessionResult
        connected_client.validate_config
        SessionResult.new(model_with_result("config valid: #{@config_path}"))
      end

      private def reconnect_obs : SessionResult
        connected_client.reconnect_obs
        @snapshot = connected_client.snapshot
        SessionResult.new(model_with_result("OBS reconnect requested"))
      rescue ex : Domain::ObsctlError
        SessionResult.new(model_with_result(ex.message || "OBS reconnect failed"))
      end

      private def connect_with_current_config(message : String) : Model
        close
        client = @client_factory.call(@config)
        client.connect
        @client = client
        @snapshot = client.snapshot
        @reconnect_attempt = 0
        @next_reconnect_at = nil
        model_with_result(message)
      rescue ex : Domain::ObsctlError
        @snapshot = disconnected_snapshot(ex.message)
        schedule_reconnect
        model_with_result(ex.message || "connection failed")
      end

      private def connected_client : SessionClient
        client = @client
        return client if client

        client = @client_factory.call(@config)
        client.connect
        @client = client
        client
      end

      private def refresh_after_success(message : String) : Model
        @snapshot = connected_client.snapshot
        model_with_result(message)
      rescue ex : Domain::ObsctlError
        model_with_result("#{message}; refresh failed: #{ex.message}")
      end

      private def model_with_result(message : String?) : Model
        @last_result = message
        Model.new(snapshot: @snapshot, last_result: message)
      end

      private def drain_events : Bool
        changed = false
        client = @client
        snapshot = @snapshot
        return false unless client

        if next_snapshot = client.next_snapshot
          @snapshot = next_snapshot
          changed = next_snapshot != snapshot
        end

        current_snapshot = @snapshot
        return changed unless current_snapshot

        while event = client.next_event
          current_snapshot = EventApplier.apply(current_snapshot, event)
          @snapshot = current_snapshot
          changed = true
        end
        changed
      end

      private def reconnect_due? : Bool
        return false unless @config.reconnect.enabled
        return false unless @snapshot.try { |snapshot| !snapshot.connected }

        reconnect_at = @next_reconnect_at
        reconnect_at.nil? || Time.utc >= reconnect_at
      end

      private def reconnect_if_due : Model
        connect_with_current_config("reconnected")
      end

      private def schedule_reconnect : Nil
        return unless @config.reconnect.enabled

        delay = Runtime::ReconnectPolicy.new(@config.reconnect).delay_for(@reconnect_attempt)
        @reconnect_attempt += 1
        @next_reconnect_at = Time.utc + delay
      end

      private def disconnected_snapshot(message : String?) : OBS::State::ObsSnapshot
        OBS::State::ObsSnapshot.new(
          connected: false,
          obs_studio_version: nil,
          obs_websocket_version: nil,
          current_scene: nil,
          scenes: [] of OBS::State::SceneState,
          audio_inputs: [] of OBS::State::AudioState,
          last_error: message
        )
      end

      private def help_text : String
        "/help /set-scene <target> /scene <target> /mute <target> /unmute <target> /toggle-mute <target> /vol <target> <0-100> /status /server-status /obs-status /reconnect /validate-config /dump-config /reload-config /connect /disconnect /quit"
      end
    end
  end
end
