require "../config/config"
require "../obs/client"
require "../obs/state/obs_snapshot"

module Obsctl
  module TUI
    abstract class SessionClient
      abstract def connect : Nil
      abstract def close : Nil
      abstract def snapshot : OBS::State::ObsSnapshot
      abstract def set_scene(name : String) : Nil
      abstract def mute(name : String, muted : Bool) : Nil
      abstract def toggle_mute(name : String) : Nil
      abstract def set_volume(name : String, percent : Int32) : Nil
      abstract def scene_names : Array(String)
      abstract def input_names : Array(String)
    end

    class ObsSessionClient < SessionClient
      def initialize(config : Config::Config)
        @client = OBS::Client.new(config)
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

      def set_scene(name : String) : Nil
        @client.set_scene(name)
      end

      def mute(name : String, muted : Bool) : Nil
        @client.mute(name, muted)
      end

      def toggle_mute(name : String) : Nil
        @client.toggle_mute(name)
      end

      def set_volume(name : String, percent : Int32) : Nil
        @client.set_volume(name, percent)
      end

      def scene_names : Array(String)
        @client.scene_names
      end

      def input_names : Array(String)
        @client.input_names
      end
    end
  end
end
