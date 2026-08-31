require "./errors"

module Obsctl
  module Domain
    # The three fields target resolution matches on, and nothing else.
    #
    # Scenes and audio inputs are stored on disk as `Config::SceneConfig` and
    # `Config::AudioInputConfig`, which also carry things resolution has no
    # opinion about (a scene's group, an input's kind, the stale flag). This
    # record is the explicit spelling of what `Aliases` actually reads, so the
    # rule can live in `domain/` without the domain layer depending on the
    # persistence shapes: the config layer converts into it (`to_target_entry`)
    # rather than the resolver reaching into the config.
    record TargetEntry, name : String, alias : String? = nil, shortcut : String? = nil

    # Resolves user targets against configured aliases, shortcuts, and OBS names.
    module Aliases
      # Resolves a scene target against the configured scenes, optionally also
      # accepting scene names discovered from the current OBS snapshot.
      def self.resolve_scene(
        entries : Array(TargetEntry),
        target : String,
        live_names : Array(String) = [] of String,
      ) : TargetEntry
        resolve(with_live_names(entries, live_names), target, TargetKind::Scene)
      end

      # Resolves an audio target using the same priority as scene resolution.
      def self.resolve_audio(
        entries : Array(TargetEntry),
        target : String,
        live_names : Array(String) = [] of String,
      ) : TargetEntry
        resolve(with_live_names(entries, live_names), target, TargetKind::AudioInput)
      end

      # Returns the configured entries plus a bare entry for every live name
      # OBS reported that no configured entry already claims.
      #
      # This is the one rule both `resolve_scene` and `resolve_audio` follow:
      # configuration wins, and anything else OBS currently has is still a
      # legal target under its own name. Matching is exact — a configured
      # entry differing only in case does not suppress the live name, because
      # `resolve` is what decides how case-insensitive matches are ranked.
      private def self.with_live_names(entries : Array(TargetEntry), live_names : Array(String)) : Array(TargetEntry)
        result = entries.dup
        live_names.each do |name|
          result << TargetEntry.new(name) unless result.any? { |entry| entry.name == name }
        end
        result
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

      # The one statement of how a target is matched: shortcut, then alias,
      # then name, and only if none of those hit exactly, alias or name
      # compared case-insensitively. An exact match anywhere outranks every
      # case-insensitive one, which is why the two are collected separately
      # rather than resolved as they are found.
      private def self.resolve(entries : Array(TargetEntry), target : String, kind : TargetKind) : TargetEntry
        exact = [] of TargetEntry
        insensitive = [] of TargetEntry

        entries.each do |entry|
          if entry.shortcut == target || entry.alias == target || entry.name == target
            exact << entry
          elsif entry.alias.try(&.downcase) == target.downcase || entry.name.downcase == target.downcase
            insensitive << entry
          end
        end

        return exact.first if exact.size == 1
        raise AliasAmbiguous.new(kind.label, target) if exact.size > 1
        return insensitive.first if insensitive.size == 1
        raise AliasAmbiguous.new(kind.label, target) if insensitive.size > 1

        raise kind.not_found(target)
      end
    end
  end
end
