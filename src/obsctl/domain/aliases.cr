require "../config/config"
require "./errors"

module Obsctl
  module Domain
    module Aliases
      def self.resolve_scene(config : Config::Config, target : String) : Config::SceneConfig
        resolve(config.scenes, target, "scene") { |entry| {entry.shortcut, entry.alias, entry.name} }
      end

      def self.resolve_audio(config : Config::Config, target : String) : Config::AudioInputConfig
        resolve(config.audio.inputs, target, "audio input") { |entry| {entry.shortcut, entry.alias, entry.name} }
      end

      private def self.resolve(entries : Array(T), target : String, kind : String, &) : T forall T
        exact = [] of T
        insensitive = [] of T

        entries.each do |entry|
          shortcut, aliaz, name = yield entry
          if shortcut == target
            exact << entry
          elsif aliaz == target
            exact << entry
          elsif name == target
            exact << entry
          elsif aliaz.try(&.downcase) == target.downcase || name.downcase == target.downcase
            insensitive << entry
          end
        end

        return exact.first if exact.size == 1
        raise AliasAmbiguous.new(kind, target) if exact.size > 1
        return insensitive.first if insensitive.size == 1
        raise AliasAmbiguous.new(kind, target) if insensitive.size > 1

        if kind == "scene"
          raise SceneNotFound.new(target)
        else
          raise AudioInputNotFound.new(target)
        end
      end

      def self.volume_percent_to_mul(percent : Int32) : Float64
        percent.to_f64 / 100.0
      end
    end
  end
end
