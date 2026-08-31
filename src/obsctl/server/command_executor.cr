require "json"
require "../config/config"
require "../config/config_dump"
require "../config/config_loader"
require "../config/config_schema"
require "../config/config_writer"
require "../domain/aliases"
require "../domain/scene_profiles"
require "../domain/volume"
require "../domain/errors"
require "../ipc/command_name"
require "../ipc/state_snapshot_codec"
require "../ipc/request"
require "../ipc/response"
require "./log_payload"
require "./obs_supervisor"
require "./state_store"

module Obsctl
  module Server
    # Executes validated IPC commands against server-owned config, state, and OBS client.
    class CommandExecutor
      JSON_SAFE_COUNTER_MAX = Int64::MAX.to_u64

      # Creates a command executor for one server runtime.
      def initialize(
        @config : Config::Config,
        @config_path : String,
        @state : StateStore,
        @supervisor : ObsSupervisor,
        @socket_path : String,
        @started_at : Time = Time.utc,
        @client_count : Proc(Int32)? = nil,
        @dropped_reconnect_diagnostic_logs : Proc(UInt64)? = nil,
        @log_broadcast : Proc(JSON::Any, Nil)? = nil,
      )
      end

      # Executes a command request and converts domain failures into IPC errors.
      def execute(request : IPC::Request) : IPC::Response
        command = request.command
        raise Domain::IpcProtocolError.new("command request missing command payload") unless command

        result = execute_command(command)
        IPC::Response.new(request.id, true, result)
      rescue ex : Domain::ObsctlError
        publish_log("warn", "command_failed", IPC::ErrorPayload.sanitize_message(ex.message || "request failed"))
        IPC::Response.new(request.id, false, nil, IPC::ErrorPayload.from_exception(ex))
      rescue ex
        publish_log("error", "command_failed", IPC::ErrorPayload.sanitize_message(ex.message || "request failed"))
        IPC::Response.new(request.id, false, nil, IPC::ErrorPayload.server_error)
      end

      alias Handler = Proc(CommandExecutor, IPC::CommandPayload, JSON::Any)

      # Every IPC command the daemon answers, and the handler that answers it.
      #
      # A table rather than a chain of `case` arms because the key set has to be
      # enumerable: `spec/obsctl/domain/command_ipc_coverage_spec.cr` checks it
      # against the names the client surfaces can actually send, so a command
      # added to `Domain::Command` and forgotten here fails the build instead of
      # failing at runtime for whoever ran it first.
      HANDLERS = {
        IPC::CommandName::PING              => Handler.new { |executor, _payload| executor.object({"message" => "pong"}) },
        IPC::CommandName::GET_SERVER_STATUS => Handler.new { |executor, _payload| executor.server_status },
        IPC::CommandName::STATUS            => Handler.new { |executor, _payload| executor.combined_status },
        IPC::CommandName::GET_OBS_STATUS    => Handler.new { |executor, _payload| executor.snapshot_json },
        IPC::CommandName::GET_SNAPSHOT      => Handler.new { |executor, _payload| executor.snapshot_json },
        IPC::CommandName::RECONNECT_OBS     => Handler.new { |executor, _payload| executor.reconnect_obs },
        IPC::CommandName::SHUTDOWN_SERVER   => Handler.new { |executor, _payload| executor.shutdown_server },

        IPC::CommandName::SET_SCENE            => Handler.new { |executor, payload| executor.set_scene(payload) },
        IPC::CommandName::SET_PROFILE          => Handler.new { |executor, payload| executor.set_profile(payload) },
        IPC::CommandName::SET_SCENE_COLLECTION => Handler.new { |executor, payload| executor.set_scene_collection(payload) },

        IPC::CommandName::MUTE        => Handler.new { |executor, payload| executor.set_mute(payload, true) },
        IPC::CommandName::UNMUTE      => Handler.new { |executor, payload| executor.set_mute(payload, false) },
        IPC::CommandName::TOGGLE_MUTE => Handler.new { |executor, payload| executor.toggle_mute(payload) },
        IPC::CommandName::SET_VOLUME  => Handler.new { |executor, payload| executor.set_volume(payload) },

        IPC::CommandName::TOGGLE_STREAM => Handler.new { |executor, _payload| executor.toggle_stream },
        IPC::CommandName::TOGGLE_RECORD => Handler.new { |executor, _payload| executor.toggle_record },
        IPC::CommandName::START_RECORD  => Handler.new { |executor, _payload| executor.start_record },
        IPC::CommandName::STOP_RECORD   => Handler.new { |executor, _payload| executor.stop_record },
        IPC::CommandName::PAUSE_RECORD  => Handler.new { |executor, _payload| executor.pause_record },
        IPC::CommandName::RESUME_RECORD => Handler.new { |executor, _payload| executor.resume_record },
        IPC::CommandName::RECORD_STATUS => Handler.new { |executor, _payload| executor.record_status },

        IPC::CommandName::VALIDATE_CONFIG => Handler.new { |executor, _payload| executor.validate_config },
        IPC::CommandName::DUMP_CONFIG     => Handler.new { |executor, _payload| executor.dump_config },
        IPC::CommandName::RELOAD_CONFIG   => Handler.new { |executor, _payload| executor.reload_config },

        IPC::CommandName::SET_SCENE_PROFILE    => Handler.new { |executor, payload| executor.set_scene_profile(payload) },
        IPC::CommandName::CLEAR_SCENE_PROFILE  => Handler.new { |executor, _payload| executor.clear_scene_profile },
        IPC::CommandName::SAVE_SCENE_PROFILE   => Handler.new { |executor, payload| executor.save_scene_profile(payload) },
        IPC::CommandName::DELETE_SCENE_PROFILE => Handler.new { |executor, payload| executor.delete_scene_profile(payload) },
        IPC::CommandName::LIST_SCENE_PROFILES  => Handler.new { |executor, _payload| executor.list_scene_profiles },
      }

      # Routes an IPC command to the handler that owns it.
      private def execute_command(command : IPC::CommandPayload) : JSON::Any
        handler = HANDLERS[command.name]?
        raise Domain::CommandParseError.new("unsupported IPC command: #{command.name}") unless handler

        handler.call(self, command)
      end

      # The handlers below are `protected` rather than `private` only because
      # `HANDLERS` calls them through an explicit receiver. They are not part of
      # the daemon's API; `execute` is.
      protected def reconnect_obs : JSON::Any
        unless @supervisor.alive? && @supervisor.reconnect
          raise Domain::ObsUnavailable.new("OBS supervisor is not running; restart the server or enable reconnect.")
        end
        object({"message" => "OBS reconnect requested"})
      end

      protected def shutdown_server : JSON::Any
        raise Domain::ShutdownDisabled.new unless @config.server.allow_remote_shutdown

        object({"message" => "server shutdown requested"})
      end

      protected def snapshot_json : JSON::Any
        IPC::StateSnapshotCodec.encode(@state.snapshot)
      end

      protected def set_scene(command : IPC::CommandPayload) : JSON::Any
        target = required_target(command)
        live_names = @state.snapshot.scenes.map(&.name)
        scene = Domain::Aliases.resolve_scene(@config, target, live_names)
        @supervisor.with_client(&.set_scene(scene.name))
        refresh_snapshot
        object({"message" => "scene set: #{scene.name}"})
      end

      protected def set_profile(command : IPC::CommandPayload) : JSON::Any
        target = required_target(command)
        @supervisor.with_client(&.set_profile(target))
        refresh_snapshot
        object({"message" => "profile set: #{target}"})
      end

      protected def set_scene_collection(command : IPC::CommandPayload) : JSON::Any
        target = required_target(command)
        @supervisor.with_client(&.set_scene_collection(target))
        refresh_snapshot
        object({"message" => "scene collection set: #{target}"})
      end

      protected def toggle_mute(command : IPC::CommandPayload) : JSON::Any
        input = resolve_audio(required_target(command))
        @supervisor.with_client(&.toggle_mute(input.name))
        refresh_snapshot
        object({"message" => "toggled mute: #{input.name}"})
      end

      protected def set_volume(command : IPC::CommandPayload) : JSON::Any
        percent = command.percent
        raise Domain::CommandParseError.new("missing volume percent") unless percent
        # The CLI and the TUI both bound this already, but the daemon is the
        # authoritative state holder and anything at all can speak the IPC
        # protocol directly, so the documented 0-100 range is enforced here too
        # — before resolving the input, so a bad request costs no OBS lookup.
        raise Domain::CommandParseError.new("volume must be from 0 to 100") unless 0 <= percent <= 100

        input = resolve_audio(required_target(command))

        @supervisor.with_client(&.set_volume(input.name, percent))
        @state.update_input_volume(input.name, Domain::Volume.percent_to_mul(percent), nil)
        object({"message" => "volume set: #{input.name} #{percent}%"})
      end

      protected def toggle_stream : JSON::Any
        active = @supervisor.with_client(&.toggle_stream)
        refresh_snapshot
        object({"message" => "streaming #{output_state(active)}"})
      end

      protected def toggle_record : JSON::Any
        active = @supervisor.with_client(&.toggle_record)
        refresh_snapshot
        object({"message" => "recording #{output_state(active)}"})
      end

      protected def start_record : JSON::Any
        @supervisor.with_client(&.start_record)
        refresh_snapshot
        object({"message" => "recording started"})
      end

      protected def stop_record : JSON::Any
        output_path = @supervisor.with_client(&.stop_record)
        refresh_snapshot
        object({"message" => output_path ? "recording stopped: #{output_path}" : "recording stopped"})
      end

      protected def pause_record : JSON::Any
        @supervisor.with_client(&.pause_record)
        refresh_snapshot
        object({"message" => "recording paused"})
      end

      protected def resume_record : JSON::Any
        @supervisor.with_client(&.resume_record)
        refresh_snapshot
        object({"message" => "recording resumed"})
      end

      protected def record_status : JSON::Any
        record_status_payload(@supervisor.with_client(&.record_status))
      end

      protected def validate_config : JSON::Any
        Config::ConfigLoader.new.load(@config_path)
        object({"message" => "config valid: #{@config_path}"})
      end

      protected def dump_config : JSON::Any
        @supervisor.with_client do |client|
          merged = Config::ConfigDump.merge(@config, client.scene_names, client.input_names)
          Config::ConfigWriter.new.write(@config_path, merged, backup: true)
          # In place, so the supervisor and the live OBS client — which
          # hold the same object — see the merged scenes and inputs too.
          @config.replace_with(merged)
        end
        refresh_snapshot
        object({"message" => "config dumped: #{@config_path}"})
      end

      protected def reload_config : JSON::Any
        @config.replace_with(Config::ConfigLoader.new.load(@config_path))
        refresh_snapshot
        object({"message" => "config reloaded: #{@config_path}"})
      end

      # Scene profiles: obsctl's own named sets of scene-visibility choices.
      #
      # None of these five reaches OBS. They edit the config file and the
      # snapshot the daemon pushes, which is what makes the dashboard's scene
      # list change without a round trip to OBS -- and what keeps every client
      # agreeing about which scenes are hidden, since they all read the answer
      # the daemon resolved rather than resolving it themselves.
      #
      # The four that edit do it on `@config.copy` and never on `@config`
      # itself: the shared object is adopted only once the file write succeeded,
      # so a command that fails partway leaves the daemon on the config it had.
      protected def set_scene_profile(command : IPC::CommandPayload) : JSON::Any
        name = scene_profile_name(required_target(command), "target")
        profile = find_scene_profile(name)
        raise Domain::ConfigInvalid.new("scene profile not found: #{name}") unless profile

        updated = @config.copy
        # The stored spelling, not the caller's: the config is the record of
        # what this profile is called, and a lookup that ignored case must not
        # rewrite the name on every use.
        updated.active_scene_profile = profile.name
        persist_config!(updated)
        object({
          "message"  => "scene profile set: #{profile.name}",
          "hidden"   => scenes_hidden_by(profile.hidden),
          "listed"   => profile.hidden.size,
          "warnings" => Config::ConfigSchema.warnings(updated),
        })
      end

      protected def clear_scene_profile : JSON::Any
        updated = @config.copy
        updated.active_scene_profile = nil
        persist_config!(updated)
        # Not an error when nothing was active: "stop filtering" is a statement
        # about the state we want, not about the state we are in.
        object({"message" => "scene profile cleared"})
      end

      protected def save_scene_profile(command : IPC::CommandPayload) : JSON::Any
        name = scene_profile_name(required_target(command), "target")
        hidden = scene_profile_hidden(command)
        rename_from = command.rename_from.try { |value| scene_profile_name(value, "rename_from") }

        updated = @config.copy
        placement = place_scene_profile(updated, name, rename_from)
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

        persist_config!(updated)
        object({
          "message"  => "scene profile saved: #{name}",
          "hidden"   => scenes_hidden_by(hidden),
          "listed"   => hidden.size,
          "created"  => placement[:index].nil?,
          "renamed"  => placement[:renamed],
          "active"   => Domain::SceneProfileNames.same?(updated.active_scene_profile, name),
          "warnings" => Config::ConfigSchema.warnings(updated),
        })
      end

      protected def delete_scene_profile(command : IPC::CommandPayload) : JSON::Any
        name = scene_profile_name(required_target(command), "target")
        profile = find_scene_profile(name)
        raise Domain::ConfigInvalid.new("scene profile not found: #{name}") unless profile

        updated = @config.copy
        updated.scene_profiles = updated.scene_profiles.reject { |entry| Domain::SceneProfileNames.same?(entry.name, profile.name) }
        # Deleting the profile in effect switches filtering off rather than
        # leaving `active_scene_profile` naming something that is gone.
        deactivated = Domain::SceneProfileNames.same?(updated.active_scene_profile, profile.name)
        updated.active_scene_profile = nil if deactivated
        persist_config!(updated)
        object({"message" => "scene profile deleted: #{profile.name}", "deactivated" => deactivated})
      end

      # Answered from the config already in memory: no file read and no file
      # lock, so a listing never queues behind a save that is still writing.
      protected def list_scene_profiles : JSON::Any
        object({
          "active"   => @config.active_scene_profile_config.try(&.name),
          "profiles" => @config.scene_profiles.map { |profile| {"name" => profile.name, "hidden" => profile.hidden} },
        })
      end

      # Where a save lands, and whether landing there is a rename.
      #
      # Four cases, and the first is the only one that refuses: renaming onto a
      # name a *different* profile already answers to would destroy that
      # profile, so it is an error rather than something done quietly -- and it
      # is raised before anything is written, so a refused save leaves no file
      # and no backup behind.
      private def place_scene_profile(config : Config::Config, name : String, rename_from : String?)
        replacing = rename_from.try { |previous| scene_profile_position(config, previous) }
        by_name = scene_profile_position(config, name)

        if replacing && by_name && replacing != by_name
          raise Domain::ConfigInvalid.new("scene profile already exists: #{name}")
        end

        return {index: replacing, renamed: !Domain::SceneProfileNames.same?(config.scene_profiles[replacing].name, name)} if replacing
        # Replacing a profile of the same name adopts the caller's spelling,
        # but is not a rename: it is the same profile saved over.
        {index: by_name, renamed: false}
      end

      private def scene_profile_position(config : Config::Config, name : String) : Int32?
        config.scene_profiles.index { |profile| Domain::SceneProfileNames.same?(profile.name, name) }
      end

      private def find_scene_profile(name : String) : Config::SceneProfileConfig?
        @config.scene_profiles.find { |profile| Domain::SceneProfileNames.same?(profile.name, name) }
      end

      # How many of these scenes will really disappear, as opposed to how many
      # the profile lists: a profile may name scenes OBS no longer has.
      # Falls back to the listed count while no snapshot has arrived, since
      # there is nothing to intersect against yet.
      private def scenes_hidden_by(hidden : Array(String)) : Int32
        scenes = @state.snapshot.scenes
        return hidden.size if scenes.empty?

        visibility = Domain::SceneVisibility.resolve([] of Tuple(String, Bool), hidden)
        scenes.count { |scene| visibility.hidden?(scene.name) }
      end

      private def scene_profile_name(value : String, label : String) : String
        error = Domain::SceneProfileNames.checked_name_error(value)
        raise Domain::CommandParseError.new("#{label} #{error}") if error

        value.strip
      end

      # The cap on a scene profile's hidden list. Chosen so that the request
      # carrying one and the snapshot it produces both stay inside the IPC
      # line limit; the same number obsctl-rs enforces.
      MAX_HIDDEN_SCENES_PER_PROFILE = 128

      # At most `MAX_HIDDEN_SCENES_PER_PROFILE` entries, so the request and the
      # snapshot it produces both stay inside the IPC line limit. Names that
      # differ only in case or padding collapse, keeping the first spelling --
      # the config records what a scene is called, and the first mention is the
      # one the caller meant.
      private def scene_profile_hidden(command : IPC::CommandPayload) : Array(String)
        entries = command.hidden
        raise Domain::CommandParseError.new("missing command hidden list") unless entries
        if entries.size > MAX_HIDDEN_SCENES_PER_PROFILE
          raise Domain::CommandParseError.new("hidden must name at most #{MAX_HIDDEN_SCENES_PER_PROFILE} scenes")
        end

        seen = Set(String).new
        entries.compact_map do |entry|
          name = scene_profile_name(entry, "hidden scene")
          normalized = Domain::SceneProfileNames.normalized_name(name)
          name if normalized && seen.add?(normalized)
        end
      end

      # Writes the edited config, then adopts it in place and republishes the
      # snapshot. In place because the supervisor, this executor and the live
      # OBS client all hold the same object; the snapshot refresh is what makes
      # a profile change reach subscribed dashboards.
      private def persist_config!(updated : Config::Config) : Nil
        Config::ConfigWriter.new.write(@config_path, updated, backup: File.exists?(@config_path))
        @config.replace_with(updated)
        refresh_snapshot
      end

      protected def set_mute(command : IPC::CommandPayload, muted : Bool) : JSON::Any
        input = resolve_audio(required_target(command))
        @supervisor.with_client(&.mute(input.name, muted))
        refresh_snapshot
        object({"message" => "#{muted ? "muted" : "unmuted"}: #{input.name}"})
      end

      private def resolve_audio(target : String) : Config::AudioInputConfig
        live_names = @state.snapshot.audio_inputs.map(&.name)
        Domain::Aliases.resolve_audio(@config, target, live_names)
      end

      # Re-reads OBS state after a command that changed it.
      #
      # A failure here does not fail the command: the command itself already
      # succeeded, and reporting "scene set" is still the truth. What it does
      # mean is that the cached snapshot is now stale, and every TUI and
      # `watch` subscriber is being served that stale view until the next
      # refresh lands. That is worth a log line — this used to be a bare
      # `rescue` with an empty body, so the one path where the daemon knowingly
      # serves stale state was also the one path it said nothing about.
      private def refresh_snapshot : Nil
        @supervisor.with_client { |client| @state.update(client.snapshot) }
      rescue ex : Domain::ObsctlError
        publish_log(
          "debug",
          "snapshot_refresh_failed",
          IPC::ErrorPayload.sanitize_message(ex.message || "failed to refresh OBS state after command")
        )
      end

      private def output_state(active : Bool?) : String
        active.nil? ? "toggled" : (active ? "started" : "stopped")
      end

      # Carries the structured record fields plus a one-line `message`, so the
      # TUI and any generic consumer can render it the same way as every other
      # command result without special-casing.
      private def record_status_payload(status : OBS::State::RecordStatus) : JSON::Any
        object({
          "message"     => "recording #{record_state_label(status)}",
          "active"      => status.active,
          "paused"      => status.paused,
          "timecode"    => status.timecode,
          "duration_ms" => status.duration_ms,
          "bytes"       => status.bytes,
        })
      end

      private def record_state_label(status : OBS::State::RecordStatus) : String
        case status.active
        when true  then status.paused == true ? "paused" : "active"
        when false then "stopped"
        else            "state unknown"
        end
      end

      protected def server_status : JSON::Any
        server_status_for(@state.snapshot)
      end

      protected def combined_status : JSON::Any
        snapshot = @state.snapshot
        object({
          "server" => server_status_for(snapshot),
          "obs"    => IPC::StateSnapshotCodec.encode(snapshot),
        })
      end

      private def server_status_for(snapshot : OBS::State::ObsSnapshot) : JSON::Any
        telemetry = @state.telemetry
        object({
          "pid"                               => Process.pid,
          "uptime_seconds"                    => (Time.utc - @started_at).total_seconds.to_i64,
          "socket_path"                       => @socket_path,
          "client_count"                      => @client_count.try(&.call) || 0,
          "dropped_reconnect_diagnostic_logs" => dropped_reconnect_diagnostic_logs,
          "obs_connected"                     => snapshot.connected,
          "reconnecting"                      => telemetry.reconnecting,
          "last_connected_at"                 => timestamp(telemetry.last_connected_at),
          "last_disconnected_at"              => timestamp(telemetry.last_disconnected_at),
          "last_reconnect_attempt_at"         => timestamp(telemetry.last_reconnect_attempt_at),
          "last_connection_failed_at"         => timestamp(telemetry.last_connection_failed_at),
          "last_error"                        => snapshot.last_error,
        })
      end

      private def dropped_reconnect_diagnostic_logs : Int64
        value = @dropped_reconnect_diagnostic_logs.try(&.call) || 0_u64
        return Int64::MAX if value > JSON_SAFE_COUNTER_MAX

        value.to_i64
      end

      private def timestamp(value : Time?) : String?
        value.try(&.to_rfc3339)
      end

      private def required_target(command : IPC::CommandPayload) : String
        command.target || raise Domain::CommandParseError.new("missing command target")
      end

      protected def object(values) : JSON::Any
        JSON.parse(values.to_json)
      end

      private def publish_log(level : String, code : String, message : String) : Nil
        @log_broadcast.try(&.call(LogPayload.build(level, code, message)))
      end
    end
  end
end
