require "../config/config"
require "../config/config_writer"
require "../domain/errors"
require "../domain/scene_profiles"

module Obsctl
  module Server
    # The config side of scene profiles: obsctl's own named sets of
    # scene-visibility choices.
    #
    # `CommandExecutor` owns the IPC request and the reply it sends back; this
    # owns the rules underneath -- where a saved profile lands, whether landing
    # there counts as a rename, how the active-profile pointer follows a rename
    # or a delete, how a hidden list is deduplicated, and when an edited config
    # becomes the daemon's config. None of that reaches OBS, which is why it
    # lives here: the rules can be exercised without a supervisor, a socket or
    # a running OBS.
    #
    # The four methods that edit work on `@config.copy` and never on `@config`
    # itself: the shared object is adopted only once the file write succeeded,
    # so a command that fails partway leaves the daemon on the config it had.
    class SceneProfileStore
      # What activating a profile settled on: the profile in the spelling the
      # config records, and the config that was written.
      record Activation, profile : Config::SceneProfileConfig, config : Config::Config

      # What a save did. The three flags are the facts a caller cannot recover
      # by reading the written config afterwards.
      record Save, config : Config::Config, created : Bool, renamed : Bool, active : Bool

      record Deletion, profile : Config::SceneProfileConfig, deactivated : Bool

      record Listing, active : String?, profiles : Array(Config::SceneProfileConfig)

      # `refresh` republishes the daemon's snapshot after a write, which is what
      # makes a profile change reach subscribed dashboards. It arrives as a proc
      # rather than as the supervisor on purpose: the supervisor is the OBS
      # connection, and `spec/obsctl/architecture_boundary_spec.cr` keeps every
      # use of it inside `command_executor.cr`.
      def initialize(
        @config : Config::Config,
        @config_path : String,
        @refresh : Proc(Nil),
      )
      end

      # Makes `name` the active profile, or fails if nothing answers to it.
      def set(name : String) : Activation
        profile = find(name)
        raise Domain::ConfigInvalid.new("scene profile not found: #{name}") unless profile

        updated = @config.copy
        # The stored spelling, not the caller's: the config is the record of
        # what this profile is called, and a lookup that ignores case must not
        # rewrite the name on every use.
        updated.active_scene_profile = profile.name
        persist!(updated)
        Activation.new(profile, updated)
      end

      # Stops filtering. Not an error when nothing was active: "stop filtering"
      # is a statement about the state we want, not about the state we are in.
      def clear : Nil
        updated = @config.copy
        updated.active_scene_profile = nil
        persist!(updated)
      end

      # Writes `name` with `hidden`, replacing whichever profile `place` says it
      # lands on, or appending when it lands on nothing.
      def save(name : String, hidden : Array(String), rename_from : String?) : Save
        updated = @config.copy
        placement = place(updated, name, rename_from)
        profile = Config::SceneProfileConfig.new(name: name, hidden: hidden)
        if index = placement[:index]
          previous = updated.scene_profiles[index]
          updated.scene_profiles[index] = profile
          # The active pointer travels with a rename, so renaming the profile
          # in effect does not quietly stop hiding scenes.
          if placement[:renamed] && Domain::SceneProfileNames.same?(updated.active_scene_profile, previous.name)
            updated.active_scene_profile = name
          end
        else
          updated.scene_profiles << profile
        end

        persist!(updated)
        Save.new(
          config: updated,
          created: placement[:index].nil?,
          renamed: placement[:renamed],
          active: Domain::SceneProfileNames.same?(updated.active_scene_profile, name)
        )
      end

      # Removes `name`, or fails if nothing answers to it.
      def delete(name : String) : Deletion
        profile = find(name)
        raise Domain::ConfigInvalid.new("scene profile not found: #{name}") unless profile

        updated = @config.copy
        updated.scene_profiles = updated.scene_profiles.reject { |entry| Domain::SceneProfileNames.same?(entry.name, profile.name) }
        # Deleting the profile in effect switches filtering off rather than
        # leaving `active_scene_profile` naming something that is gone.
        deactivated = Domain::SceneProfileNames.same?(updated.active_scene_profile, profile.name)
        updated.active_scene_profile = nil if deactivated
        persist!(updated)
        Deletion.new(profile, deactivated)
      end

      # Answered from the config already in memory: no file read and no file
      # lock, so a listing never queues behind a save that is still writing.
      def listing : Listing
        Listing.new(@config.active_scene_profile_config.try(&.name), @config.scene_profiles)
      end

      # Names that differ only in case or padding collapse, keeping the first
      # spelling -- the config records what a scene is called, and the first
      # mention is the one the caller meant.
      def normalize_hidden(names : Array(String)) : Array(String)
        seen = Set(String).new
        names.compact_map do |name|
          normalized = Domain::SceneProfileNames.normalized_name(name)
          name if normalized && seen.add?(normalized)
        end
      end

      # Where a save lands, and whether landing there is a rename.
      #
      # Four cases, and the first is the only one that refuses: renaming onto a
      # name a *different* profile already answers to would destroy that
      # profile, so it is an error rather than something done quietly -- and it
      # is raised before anything is written, so a refused save leaves no file
      # and no backup behind.
      private def place(config : Config::Config, name : String, rename_from : String?)
        replacing = rename_from.try { |previous| position(config, previous) }
        by_name = position(config, name)

        if replacing && by_name && replacing != by_name
          raise Domain::ConfigInvalid.new("scene profile already exists: #{name}")
        end

        return {index: replacing, renamed: !Domain::SceneProfileNames.same?(config.scene_profiles[replacing].name, name)} if replacing
        # Replacing a profile of the same name adopts the caller's spelling,
        # but is not a rename: it is the same profile saved over.
        {index: by_name, renamed: false}
      end

      private def position(config : Config::Config, name : String) : Int32?
        config.scene_profiles.index { |profile| Domain::SceneProfileNames.same?(profile.name, name) }
      end

      private def find(name : String) : Config::SceneProfileConfig?
        @config.scene_profiles.find { |profile| Domain::SceneProfileNames.same?(profile.name, name) }
      end

      # Writes the edited config, then adopts it in place and republishes the
      # snapshot. In place because the supervisor, the command executor and the
      # live OBS client all hold the same object.
      private def persist!(updated : Config::Config) : Nil
        Config::ConfigWriter.new.write(@config_path, updated, backup: File.exists?(@config_path))
        @config.replace_with(updated)
        @refresh.call
      end
    end
  end
end
