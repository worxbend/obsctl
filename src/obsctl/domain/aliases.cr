require "../config/config"
require "./errors"

module Obsctl
  module Domain
    # Resolves user targets against configured aliases, shortcuts, and OBS names.
    module Aliases
      # Resolves a scene target using shortcut, alias, name, then case-insensitive
      # alias/name matching.
      def self.resolve_scene(config : Config::Config, target : String) : Config::SceneConfig
        resolve(config.scenes, target, TargetKind::Scene) { |entry| {entry.shortcut, entry.alias, entry.name} }
      end

      # Resolves configured aliases first while also accepting scene names
      # discovered from the current OBS snapshot.
      def self.resolve_scene(
        config : Config::Config,
        target : String,
        live_names : Array(String),
      ) : Config::SceneConfig
        entries = config.scenes.dup
        live_names.each do |name|
          entries << Config::SceneConfig.new(name) unless entries.any? { |entry| entry.name == name }
        end
        resolve(entries, target, TargetKind::Scene) { |entry| {entry.shortcut, entry.alias, entry.name} }
      end

      # Resolves an audio target using the same priority as scene resolution.
      def self.resolve_audio(config : Config::Config, target : String) : Config::AudioInputConfig
        resolve(config.audio.inputs, target, TargetKind::AudioInput) { |entry| {entry.shortcut, entry.alias, entry.name} }
      end

      # Resolves configured aliases first while also accepting input names
      # discovered from the current OBS snapshot.
      def self.resolve_audio(
        config : Config::Config,
        target : String,
        live_names : Array(String),
      ) : Config::AudioInputConfig
        entries = config.audio.inputs.dup
        live_names.each do |name|
          entries << Config::AudioInputConfig.new(name) unless entries.any? { |entry| entry.name == name }
        end
        resolve(entries, target, TargetKind::AudioInput) { |entry| {entry.shortcut, entry.alias, entry.name} }
      end

      # What kind of thing is being looked up.
      #
      # This carries both halves of what resolution needs on failure: the word
      # to put in an "ambiguous" message, and which not-found error to raise.
      # It used to be a bare `String` that the resolver compared against
      # `"scene"` to pick the exception, which meant the human wording of a
      # message and the type of the error were the same decision — rename the
      # label and you silently change which error callers see.
      enum TargetKind
        Scene
        AudioInput

        def label : String
          scene? ? "scene" : "audio input"
        end

        def not_found(target : String) : ObsctlError
          scene? ? SceneNotFound.new(target) : AudioInputNotFound.new(target)
        end
      end

      private def self.resolve(entries : Array(T), target : String, kind : TargetKind, &) : T forall T
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
        raise AliasAmbiguous.new(kind.label, target) if exact.size > 1
        return insensitive.first if insensitive.size == 1
        raise AliasAmbiguous.new(kind.label, target) if insensitive.size > 1

        raise kind.not_found(target)
      end

      # Converts user-facing 0-100 volume to obs-websocket multiplier form.
      def self.volume_percent_to_mul(percent : Int32) : Float64
        percent.to_f64 / 100.0
      end

      # Converts an obs-websocket multiplier back to the user-facing 0-100
      # scale, which is the only volume obsctl ever shows or accepts.
      #
      # Clamped because the multiplier is not bounded at 1.0: OBS allows gain
      # above unity, and a slider pushed past it would otherwise render as a
      # percentage over 100 that no obsctl command could ask for.
      def self.volume_mul_to_percent(mul : Float64) : Int32
        (mul * 100).round.to_i32.clamp(0, 100)
      end
    end
  end
end
