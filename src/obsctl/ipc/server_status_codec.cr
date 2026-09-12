require "json"
require "../obs/state/record_status"

module Obsctl
  module IPC
    # The `server-status` result payload, in both directions.
    #
    # This is the published language for how the daemon describes itself: the
    # daemon encodes into it, the CLI decodes it back to print it. The two
    # halves are one contract and now live in one file, because they only work
    # if they agree about every key name, and they used to be written a layer
    # apart -- the encoder in `Server::CommandExecutor`, the reader in
    # `CLI::StatusPresenter` -- with nothing but care keeping twelve key names
    # in step. Nothing would have caught the drift either: the golden CLI
    # fixtures run the client against a canned payload, so a key renamed on the
    # daemon side would have quietly rendered as a dash instead of failing.
    # `state_snapshot_codec.cr` states the same reasoning for the `state` topic.
    #
    # `docs/commands.md` freezes this shape; the round trip is proven in
    # `spec/obsctl/ipc/server_status_codec_spec.cr`.
    #
    # Every field is nilable because decoding is lenient on purpose: a client
    # may be talking to an older or a newer daemon, and a field that daemon
    # does not publish should read as "unknown" rather than fail the command.
    # What "unknown" then looks like is the reader's business -- the CLI prints
    # a dash for most fields, `0` for a missing client count and `false` for
    # the two flags.
    record ServerStatus,
      pid : Int64? = nil,
      uptime_seconds : Int64? = nil,
      socket_path : String? = nil,
      client_count : Int32? = nil,
      dropped_reconnect_diagnostic_logs : Int64? = nil,
      obs_connected : Bool? = nil,
      reconnecting : Bool? = nil,
      last_connected_at : String? = nil,
      last_disconnected_at : String? = nil,
      last_reconnect_attempt_at : String? = nil,
      last_connection_failed_at : String? = nil,
      last_error : String? = nil do
      # Reads a payload however the daemon that sent it spelled things,
      # answering nil for anything absent, null, or of the wrong JSON type.
      def self.decode(data : JSON::Any) : ServerStatus
        new(
          pid: data["pid"]?.try(&.as_i64?),
          uptime_seconds: data["uptime_seconds"]?.try(&.as_i64?),
          socket_path: data["socket_path"]?.try(&.as_s?),
          client_count: data["client_count"]?.try(&.as_i?),
          dropped_reconnect_diagnostic_logs: data["dropped_reconnect_diagnostic_logs"]?.try(&.as_i64?),
          obs_connected: data["obs_connected"]?.try(&.as_bool?),
          reconnecting: data["reconnecting"]?.try(&.as_bool?),
          last_connected_at: data["last_connected_at"]?.try(&.as_s?),
          last_disconnected_at: data["last_disconnected_at"]?.try(&.as_s?),
          last_reconnect_attempt_at: data["last_reconnect_attempt_at"]?.try(&.as_s?),
          last_connection_failed_at: data["last_connection_failed_at"]?.try(&.as_s?),
          last_error: data["last_error"]?.try(&.as_s?)
        )
      end

      # Writes the frozen wire shape: all twelve keys, in this order, with an
      # absent value spelled `null` rather than omitted.
      def encode : JSON::Any
        JSON::Any.new({
          "pid"                               => json_any(pid),
          "uptime_seconds"                    => json_any(uptime_seconds),
          "socket_path"                       => json_any(socket_path),
          "client_count"                      => json_any(client_count),
          "dropped_reconnect_diagnostic_logs" => json_any(dropped_reconnect_diagnostic_logs),
          "obs_connected"                     => json_any(obs_connected),
          "reconnecting"                      => json_any(reconnecting),
          "last_connected_at"                 => json_any(last_connected_at),
          "last_disconnected_at"              => json_any(last_disconnected_at),
          "last_reconnect_attempt_at"         => json_any(last_reconnect_attempt_at),
          "last_connection_failed_at"         => json_any(last_connection_failed_at),
          "last_error"                        => json_any(last_error),
        } of String => JSON::Any)
      end

      private def json_any(value : (Bool | Int32 | Int64 | String)?) : JSON::Any
        JSON::Any.new(value)
      end
    end

    # The `record-status` result payload, in both directions, for the same
    # reason `ServerStatus` above holds both halves: five key names the daemon
    # writes and the CLI reads, and nothing else linking them.
    #
    # The value carried is `OBS::State::RecordStatus`, the type the daemon
    # already has and the type a reader already wants, so this stays a pair of
    # functions rather than a second record shaped exactly like the first.
    module RecordStatusCodec
      # Writes the frozen wire shape.
      #
      # `message` leads the object and is derived rather than stored: every
      # consumer of a command result knows how to print its `message`, so
      # shipping one alongside the structured fields means the TUI and any
      # generic client render this command like all the others.
      def self.encode(status : OBS::State::RecordStatus) : JSON::Any
        JSON::Any.new({
          "message"     => JSON::Any.new("recording #{status.state("state unknown")}"),
          "active"      => JSON::Any.new(status.active),
          "paused"      => JSON::Any.new(status.paused),
          "timecode"    => JSON::Any.new(status.timecode),
          "duration_ms" => JSON::Any.new(status.duration_ms),
          "bytes"       => JSON::Any.new(status.bytes),
        } of String => JSON::Any)
      end

      # Reads the structured fields back, leniently; `message` is not read
      # because it is derivable from them.
      def self.decode(data : JSON::Any) : OBS::State::RecordStatus
        OBS::State::RecordStatus.new(
          active: data["active"]?.try(&.as_bool?),
          paused: data["paused"]?.try(&.as_bool?),
          timecode: data["timecode"]?.try(&.as_s?),
          duration_ms: data["duration_ms"]?.try(&.as_i64?),
          bytes: data["bytes"]?.try(&.as_i64?)
        )
      end
    end
  end
end
