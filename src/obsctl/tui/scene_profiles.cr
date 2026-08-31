require "../domain/scene_profiles"

module Obsctl
  module TUI
    # A named set of scenes the dashboard keeps out of its scene list.
    #
    # These are obsctl's own profiles. They are not OBS profiles (the panel the
    # dashboard shows as "Profiles", switched with SET_PROFILE) and not OBS
    # scene collections. Nothing here reaches OBS or the daemon: the daemon
    # keeps reporting every scene and the dashboard decides which of them it
    # draws, which is why hiding a scene needs no protocol change and takes
    # effect without a round trip.
    record SceneProfile, name : String, hidden : Set(String)

    # Every profile the dashboard knows about, plus which one is in effect.
    #
    # Deliberately free of any `config` dependency so `model.cr` can require it
    # without dragging the config layer into the model. Translating to and from
    # the on-disk shape is `SceneProfilePersistence`'s job.
    #
    # Every operation returns a new value instead of mutating, so applying an
    # edit is one assignment on the model.
    struct SceneProfiles
      getter profiles : Array(SceneProfile)
      # The profile in effect, or nil for "filter nothing here".
      getter active : String?

      def self.empty : self
        new
      end

      def initialize(@profiles = [] of SceneProfile, @active = nil)
      end

      # nil when nothing is active, and also when `active` names a profile that
      # is not in the list: a hand-edited config file has to degrade to "every
      # scene visible" rather than to an empty scene list.
      def active_profile : SceneProfile?
        name = @active
        return unless name
        @profiles.find { |profile| profile.name == name }
      end

      # The position of the profile this name refers to, matched the way the
      # daemon matches it -- trimmed and case-insensitively -- rather than by
      # exact spelling.
      #
      # Exact spelling was a data-loss bug. The editor refuses to save a draft
      # over a profile it did not come from, but with an exact check a draft
      # named "Streaming" saw no existing "streaming", passed the refusal, and
      # the daemon then matched the two names and overwrote the saved
      # profile's hidden scenes with the draft's. The dashboard has to ask the
      # same question the daemon will answer.
      def index_of(name : String) : Int32?
        @profiles.index { |profile| Domain::SceneProfileNames.same?(profile.name, name) }
      end

      # Replaces the profile with this name, or appends it when it is new, so
      # "save" is one operation whether the user is editing or creating.
      def upsert(name : String, hidden : Set(String)) : self
        profile = SceneProfile.new(name, hidden.dup)
        updated = @profiles.dup
        if index = index_of(name)
          updated[index] = profile
        else
          updated << profile
        end
        SceneProfiles.new(updated, @active)
      end

      # Removes a profile, and stops pointing at it if it was the active one.
      #
      # Clearing `active` here rather than leaving it dangling: the config
      # schema treats an `active` naming no profile as a warning and the
      # dashboard degrades it to "every scene visible", so a delete that left
      # the name behind would write a file that warns about itself.
      def delete(name : String) : self
        updated = @profiles.reject { |profile| profile.name == name }
        SceneProfiles.new(updated, @active == name ? nil : @active)
      end

      def activate(name : String?) : self
        SceneProfiles.new(@profiles, name)
      end
    end
  end
end
