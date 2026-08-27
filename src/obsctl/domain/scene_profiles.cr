module Obsctl
  module Domain
    # Which scenes are hidden from the scene list right now.
    #
    # OBS setups often contain "utility" scenes that only exist to be nested
    # inside other scenes. Listing them next to the scenes a user actually
    # switches to is noise, so obsctl lets them be hidden -- either permanently,
    # with the per-scene `hidden` flag in the config, or through a named
    # **scene profile**: a saved set of visibility choices that can be switched
    # as a unit. (A scene profile is an obsctl concept and has nothing to do
    # with an OBS profile, which is the OBS-side setting `set-profile` changes.)
    #
    # Two sources of truth for the same question is how a UI ends up disagreeing
    # with the daemon about what should be on screen, so there is exactly one
    # answer here: build a `SceneVisibility` from the config once, then ask it.
    # Nothing else may decide whether a scene is hidden.
    #
    # This file deliberately requires nothing -- no `config`, no `obs`, no
    # `ipc`. The rule it encodes is about names and booleans, not about any
    # particular wire type, and keeping it that way is what lets the config
    # layer, the daemon and the dashboard all share it.
    module SceneProfileNames
      # The longest a scene or profile name may be, counted in characters.
      # Matches `Domain::CommandParser::MAX_TARGET_TOKEN_LENGTH`; the two are
      # the same rule applied on either side of the wire.
      MAX_NAME_LENGTH = 256

      extend self

      # The name as it should be stored and sent onwards: trimmed, case
      # preserved. `nil` when the name cannot be used at all.
      #
      # Case is preserved because a scene called "Main Camera" has to reach OBS
      # spelled that way; only *matching* is case-insensitive.
      def checked_name(value : String) : String?
        return unless checked_name_error(value).nil?

        value.strip
      end

      # Why `checked_name` would reject this name, or `nil` when it would not.
      #
      # Split out from `checked_name` because config validation has to tell the
      # user which rule a name broke, while `SceneVisibility` only needs to know
      # that it broke one. The sentences match the ones the command parser
      # already produces for the same rules.
      def checked_name_error(value : String) : String?
        # Before the trim, not after: a name with a tab in it is unusable even
        # when the tab is on the end and trimming would have hidden the problem.
        return "must not contain control characters" if value.each_char.any?(&.control?)

        trimmed = value.strip
        return "must not be blank" if trimmed.empty?
        # Characters, not bytes, so a name of accented letters is measured the
        # way a reader would count it.
        return "must not be longer than #{MAX_NAME_LENGTH} characters" if trimmed.size > MAX_NAME_LENGTH

        nil
      end

      # The form two names are compared in: trimmed and folded to lower case.
      # `nil` when the name cannot be used at all.
      #
      # ASCII-only folding, deliberately. Crystal's `String#downcase` is
      # Unicode-aware, which would fold "İ" to "i̇" and make two scenes that
      # OBS considers different collide here. The daemon and obsctl-rs must
      # agree on what "the same name" means, and obsctl-rs folds ASCII only.
      def normalized_name(value : String) : String?
        checked_name(value).try(&.downcase(Unicode::CaseOptions::ASCII))
      end
    end

    # The resolved answer to "is this scene hidden", built once from the config.
    #
    # Holds nothing but a set of normalized names: no ordering, no original
    # spellings, no profile identity. Cheap to copy and to ask, so one resolved
    # value is passed around rather than re-derived, and every consumer working
    # from one snapshot gives the same answer.
    struct SceneVisibility
      # Normalized names of the scenes that are hidden.
      @hidden : Set(String)

      def initialize(@hidden = Set(String).new)
      end

      # Builds the hidden set from the config's two inputs.
      #
      # `baseline` is `{scene name, that scene's hidden flag}` for every
      # configured scene -- visible ones included, because the filtering happens
      # here.
      #
      # `active` is the active profile's hidden list, or `nil` for "no profile
      # is in effect". The difference between `nil` and an empty array is
      # load-bearing: `nil` means the per-scene flags decide, while `[] of
      # String` is a profile that hides nothing, which is how "show every scene"
      # is expressed.
      #
      # An active profile **replaces** the baseline rather than adding to it.
      # That is what lets a profile reveal a scene `scenes:` marks hidden, and
      # what makes "show everything" expressible as a profile with an empty
      # list. A union could do neither.
      #
      # Names that cannot be normalized are dropped rather than rejected:
      # config validation already reported them, and one unusable entry must
      # not decide the visibility of every other scene.
      def self.resolve(baseline : Enumerable(Tuple(String, Bool)), active : Array(String)?) : self
        names =
          if active
            active.compact_map { |name| SceneProfileNames.normalized_name(name) }
          else
            baseline.compact_map do |(name, hidden)|
              SceneProfileNames.normalized_name(name) if hidden
            end
          end

        new(names.to_set)
      end

      # Whether this scene is hidden, given the name spelled however OBS spells
      # it.
      #
      # A name that cannot be normalized reports visible rather than raising: it
      # cannot have been put in the hidden set either, and showing an oddly
      # named scene is the recoverable outcome.
      def hidden?(scene_name : String) : Bool
        name = SceneProfileNames.normalized_name(scene_name)
        return false unless name

        @hidden.includes?(name)
      end

      # How many distinct scenes are hidden, for a caller that has to show the
      # number. Counts the resolved set, which may still name scenes that no
      # longer exist in OBS.
      def hidden_count : Int32
        @hidden.size
      end

      def ==(other : self) : Bool
        @hidden == other.@hidden
      end
    end
  end
end
