require "../../state/obs_snapshot"
require "../../domain/volume"
require "../scene_picker"
require "../scene_profiles"
require "../scene_profile_list"
require "./focus_panel"

module Obsctl
  module TUI
    # What the daemon last reported, and every list derived from it.
    #
    # The derivation rules live here, next to the snapshot they derive from:
    # the daemon has already decided which scenes a profile hides, and a
    # client that asks the question again is exactly how the two end up
    # disagreeing about what should be on screen. So does cache invalidation,
    # which is the snapshot's business alone -- a fresh snapshot is the only
    # thing that can make a derived list stale.
    class DashboardState
      getter snapshot : State::ObsSnapshot?

      # The scene a pushed snapshot just switched to, and the frame it
      # switched on. The scenes panel flashes the name for a few frames;
      # storing the frame rather than counting down a timer keeps the flash a
      # pure function of the clock.
      property scene_flash : Tuple(String, UInt64)?

      # Volume edits the user has made but the daemon has not acknowledged yet.
      #
      # A volume keypress paints the new level immediately and only sends the
      # OBS command once the keys stop coming, so for up to that debounce
      # window the screen holds a level the daemon has never heard of. The
      # daemon pushes a fresh snapshot every couple of seconds and after any
      # other client's command, and such a push carries the *old* level. This
      # map is what lets `audio_inputs` tell "the daemon disagrees" apart from
      # "the daemon has not been told yet", instead of relying on the push
      # happening to miss the debounce window.
      @pending_volumes : Hash(String, Int32)
      # Derived collections are cached until the snapshot or pending preview
      # they depend on changes, so the render loop can ask for them many times
      # per frame without rebuilding the same arrays each time.
      @audio_inputs_cache : Array(State::AudioState)?
      @scenes_cache : Array(State::SceneState)?
      @scene_profiles_cache : SceneProfiles?
      @scene_picker_entries_cache : Array(ScenePicker::Entry)?
      @scene_profile_list_entries_cache : Array(SceneProfileList::Entry)?

      def initialize
        @snapshot = nil
        @scene_flash = nil
        @pending_volumes = {} of String => Int32
        @audio_inputs_cache = nil
        @scenes_cache = nil
        @scene_profiles_cache = nil
        @scene_picker_entries_cache = nil
        @scene_profile_list_entries_cache = nil
      end

      # The single place a snapshot is stored, so the pending-edit rule cannot
      # be skipped by a caller that assigns the field directly: an edit the
      # user is still making is newer than any snapshot the daemon computed
      # before that edit reached it, and therefore wins.
      #
      # Swapping and invalidating is all this does; re-seeking the cursors
      # onto the scenes they were pointing at is the composition root's job,
      # because the cursors belong to the focus and picker states.
      def adopt(snapshot : State::ObsSnapshot?) : Nil
        @snapshot = snapshot
        invalidate_snapshot_caches
      end

      # The scene picker's rows, cached until the snapshot changes.
      #
      # Input resolution, the widget and the hit test all ask for them during
      # one frame, so caching keeps that frame from rebuilding the same labels
      # several times while still invalidating before the next snapshot can
      # change which scene a label points at.
      def scene_picker_entries : Array(ScenePicker::Entry)
        @scene_picker_entries_cache ||= ScenePicker.entries(scenes)
      end

      # Cached for the same reason `scene_picker_entries` is: several callers
      # need one frame-stable answer, and only a fresh snapshot can make that
      # answer stale.
      def scene_profile_list_entries : Array(SceneProfileList::Entry)
        @scene_profile_list_entries_cache ||= SceneProfileList.entries(scene_profiles)
      end

      # Every scene the daemon reported, hidden ones included. The scene-profile
      # editor lists these; everything else on the dashboard uses `scenes`.
      def all_scenes : Array(State::SceneState)
        @snapshot.try(&.scenes) || [] of State::SceneState
      end

      # The scenes the dashboard draws.
      #
      # One `reject`, because the daemon has already done the deciding: it
      # resolves the active profile against the per-scene `hidden` flags -- an
      # active profile replaces those flags rather than adding to them -- and
      # ships the answer as `hidden` on each scene. The dashboard asking the
      # same question again is exactly how a client ends up disagreeing with
      # the daemon about what should be on screen.
      def scenes : Array(State::SceneState)
        @scenes_cache ||= all_scenes.reject(&.hidden)
      end

      # The saved scene profiles the daemon reported, and which one is in
      # effect. Read from the snapshot rather than from the config file so that
      # the dashboard, the CLI and a second dashboard all see one answer, and so
      # that a profile saved anywhere shows up here without a reload.
      def scene_profiles : SceneProfiles
        @scene_profiles_cache ||= begin
          if snapshot = @snapshot
            SceneProfiles.new(
              snapshot.scene_profiles.map { |profile| SceneProfile.new(profile.name, profile.hidden.to_set) },
              snapshot.active_scene_profile
            )
          else
            SceneProfiles.empty
          end
        end
      end

      def audio_inputs : Array(State::AudioState)
        @audio_inputs_cache ||= begin
          if snapshot = @snapshot
            with_pending_volumes(snapshot.audio_inputs)
          else
            [] of State::AudioState
          end
        end
      end

      def profiles : Array(String)
        @snapshot.try(&.profiles) || [] of String
      end

      def current_profile : String?
        @snapshot.try(&.current_profile)
      end

      def scene_collections : Array(String)
        @snapshot.try(&.scene_collections) || [] of String
      end

      def current_scene_collection : String?
        @snapshot.try(&.current_scene_collection)
      end

      def current_scene : String?
        @snapshot.try(&.current_scene)
      end

      def obs_connected? : Bool
        @snapshot.try(&.connected) || false
      end

      def streaming? : Bool
        @snapshot.try(&.output.streaming) || false
      end

      def recording? : Bool
        @snapshot.try(&.output.recording) || false
      end

      def stats : State::ObsStats?
        @snapshot.try(&.stats)
      end

      def stream_bitrate_kbps : Float64?
        @snapshot.try(&.stream_bitrate_kbps)
      end

      def stream_duration_ms : Int64?
        @snapshot.try(&.stream_duration_ms)
      end

      def record_duration_ms : Int64?
        @snapshot.try(&.record_duration_ms)
      end

      # Exhaustive `in` rather than `when`/`else`: a fifth panel then becomes a
      # compile error here instead of silently counting scene collections.
      def item_count(panel : FocusPanel) : Int32
        case panel
        in .scenes?      then scenes.size
        in .audio?       then audio_inputs.size
        in .profiles?    then profiles.size
        in .collections? then scene_collections.size
        end
      end

      # Applies an optimistic volume value so rapid keyboard changes render
      # immediately while the debounced OBS command is still pending.
      def preview_audio_volume(input_name : String, percent : Int32) : Nil
        return unless @snapshot

        bounded = percent.clamp(0, 100)
        @pending_volumes[input_name] = bounded
        invalidate_audio_cache
      end

      # Forgets the optimistic value for one input, because the command that
      # carried it has finished and the daemon's own snapshots are now the
      # better answer.
      def settle_volume(input_name : String) : Nil
        return unless @pending_volumes.delete(input_name)

        invalidate_audio_cache
      end

      private def with_pending_volumes(inputs : Array(State::AudioState)) : Array(State::AudioState)
        return inputs if @pending_volumes.empty?

        updated = inputs.dup
        changed = false
        updated.each_with_index do |input, index|
          percent = @pending_volumes[input.name]?
          next unless percent
          changed = true
          updated[index] = input.copy_with(
            volume_mul: Domain::Volume.percent_to_mul(percent),
            volume_percent: percent
          )
        end
        changed ? updated : inputs
      end

      private def invalidate_snapshot_caches : Nil
        @audio_inputs_cache = nil
        @scenes_cache = nil
        @scene_profiles_cache = nil
        @scene_picker_entries_cache = nil
        @scene_profile_list_entries_cache = nil
      end

      private def invalidate_audio_cache : Nil
        @audio_inputs_cache = nil
      end
    end
  end
end
