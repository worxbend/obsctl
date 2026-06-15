require "./model"
require "./session_client"
require "../config/config_dump"
require "../config/config_loader"
require "../config/config_writer"
require "../domain/aliases"
require "../domain/command"
require "../domain/command_parser"
require "../domain/command_result"
require "../domain/errors"

module Obsctl
  module TUI
    record SessionResult, model : Model, quit : Bool = false

    class Session
      getter config

      def initialize(
        @config : Config::Config,
        @config_path : String,
        @client_factory : Proc(Config::Config, SessionClient) = ->(config : Config::Config) {
          ObsSessionClient.new(config).as(SessionClient)
        },
      )
        @parser = Domain::CommandParser.new
        @snapshot = nil.as(OBS::State::ObsSnapshot?)
        @client = nil.as(SessionClient?)
      end

      def start : Model
        connect_with_current_config("Enter command, /quit to exit.")
      end

      def execute_line(line : String) : SessionResult
        command = @parser.parse(line)
        execute(command)
      rescue ex : Domain::ObsctlError
        SessionResult.new(model_with_result(ex.message || "command failed"))
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
          scene = Domain::Aliases.resolve_scene(@config, command.target)
          connected_client.set_scene(scene.name)
          SessionResult.new(refresh_after_success("scene set: #{scene.name}"))
        when Domain::MuteCommand
          input = Domain::Aliases.resolve_audio(@config, command.target)
          connected_client.mute(input.name, true)
          SessionResult.new(refresh_after_success("muted: #{input.name}"))
        when Domain::UnmuteCommand
          input = Domain::Aliases.resolve_audio(@config, command.target)
          connected_client.mute(input.name, false)
          SessionResult.new(refresh_after_success("unmuted: #{input.name}"))
        when Domain::ToggleMuteCommand
          input = Domain::Aliases.resolve_audio(@config, command.target)
          connected_client.toggle_mute(input.name)
          SessionResult.new(refresh_after_success("toggled mute: #{input.name}"))
        when Domain::VolumeCommand
          input = Domain::Aliases.resolve_audio(@config, command.target)
          connected_client.set_volume(input.name, command.percent)
          SessionResult.new(refresh_after_success("volume set: #{input.name} #{command.percent}%"))
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
        @config = Config::ConfigLoader.new.load(@config_path)
        close
        SessionResult.new(connect_with_current_config("config reloaded: #{@config_path}"))
      end

      private def dump_config : SessionResult
        client = connected_client
        merged = Config::ConfigDump.merge(@config, client.scene_names, client.input_names)
        Config::ConfigWriter.new.write(@config_path, merged, backup: true)
        @config = merged
        SessionResult.new(refresh_after_success("config dumped: #{@config_path}"))
      end

      private def connect_with_current_config(message : String) : Model
        close
        client = @client_factory.call(@config)
        client.connect
        @client = client
        @snapshot = client.snapshot
        model_with_result(message)
      rescue ex : Domain::ObsctlError
        @snapshot = disconnected_snapshot(ex.message)
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
        Model.new(snapshot: @snapshot, last_result: message)
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
        "/help /set-scene <target> /scene <target> /mute <target> /unmute <target> /toggle-mute <target> /vol <target> <0-100> /dump-config /reload-config /status /connect /disconnect /quit"
      end
    end
  end
end
