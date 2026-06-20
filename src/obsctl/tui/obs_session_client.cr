require "./session_client"
require "../config/config"
require "../domain/aliases"
require "../obs/client"

module Obsctl
  module TUI
    # Direct OBS adapter retained only for explicit embedded-style sessions and tests.
    class ObsSessionClient < SessionClient
      def initialize(@config : Config::Config)
        @client = OBS::Client.new(@config)
      end

      def connect : Nil
        @client.connect
      end

      def close : Nil
        @client.close
      end

      def snapshot : OBS::State::ObsSnapshot
        @client.snapshot
      end

      def set_scene(target : String) : Nil
        scene = Domain::Aliases.resolve_scene(@config, target)
        @client.set_scene(scene.name)
      end

      def mute(target : String, muted : Bool) : Nil
        input = Domain::Aliases.resolve_audio(@config, target)
        @client.mute(input.name, muted)
      end

      def toggle_mute(target : String) : Nil
        input = Domain::Aliases.resolve_audio(@config, target)
        @client.toggle_mute(input.name)
      end

      def set_volume(target : String, percent : Int32) : Nil
        input = Domain::Aliases.resolve_audio(@config, target)
        @client.set_volume(input.name, percent)
      end

      def scene_names : Array(String)
        @client.scene_names
      end

      def input_names : Array(String)
        @client.input_names
      end

      def next_event : OBS::Protocol::Event?
        select
        when event = @client.events.receive
          event
        when timeout(0.milliseconds)
          nil
        end
      end

      def next_snapshot : OBS::State::ObsSnapshot?
        nil
      end

      def next_log : String?
        nil
      end

      def dump_config : Nil
      end

      def reload_config : Nil
      end

      def reconnect_obs : Nil
        close
        connect
      end

      def validate_config : Nil
      end
    end
  end
end
