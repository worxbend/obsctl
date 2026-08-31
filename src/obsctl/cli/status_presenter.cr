require "json"
require "../ipc/server_status_codec"
require "./color"

module Obsctl
  module CLI
    # Renders daemon status payloads as human-readable terminal text.
    #
    # Split out of `ClientCommands`, which was both the IPC gateway and the
    # renderer and so had two unrelated reasons to change: the wire protocol,
    # and how status looks in a terminal. Nothing here talks to the daemon; it
    # takes the decoded result of a command and returns the text for it.
    #
    # Everything reads defensively because the payload is whatever the daemon
    # sent. A field the running daemon does not publish — an older build, a
    # newer one — renders as a dash rather than crashing the client. For the
    # two payloads with a fixed field list, `server-status` and `record-status`,
    # that leniency lives in `ipc/server_status_codec.cr` alongside the daemon's
    # encoders, so the key names cannot drift apart; the OBS sections below
    # still read `JSON::Any` directly.
    class StatusPresenter
      VOLUME_BAR_SEGMENTS = 10

      def initialize(@palette : Palette = Palette.monochrome)
      end

      # Renders the combined `status` payload, falling back to the OBS section
      # when the daemon sent only that.
      def combined_status(result : JSON::Any) : String
        server = result["server"]?
        obs = result["obs"]?
        return obs_status(result) unless server && obs

        bold = @palette.bold
        reset = @palette.reset
        [
          "#{bold}#{@palette.blue}── server ──────────────────────────#{reset}",
          indent(server_status(server)),
          "#{bold}#{@palette.cyan}── obs ─────────────────────────────#{reset}",
          indent(obs_status(obs)),
        ].join('\n')
      end

      def obs_status(result : JSON::Any) : String
        heading = "#{@palette.bold}#{@palette.cyan}"
        reset = @palette.reset

        lines = [] of String
        lines << connection_line(result)
        lines << "current_scene: #{@palette.bright_white}#{result["current_scene"]?.try(&.as_s?) || "-"}#{reset}"
        lines << "#{heading}Scenes:#{reset}"
        result["scenes"]?.try(&.as_a?).try { |scenes| scenes.each { |scene| lines << scene_line(scene) } }
        lines << "#{heading}Audio:#{reset}"
        result["audio_inputs"]?.try(&.as_a?).try { |inputs| inputs.each { |input| lines << audio_line(input) } }
        lines.join('\n')
      end

      def server_status(result : JSON::Any) : String
        status = IPC::ServerStatus.decode(result)
        [
          "pid: #{text(status.pid)}",
          "uptime_seconds: #{text(status.uptime_seconds)}",
          "socket_path: #{text(status.socket_path)}",
          "client_count: #{status.client_count || 0}",
          "dropped_reconnect_diagnostic_logs: #{text(status.dropped_reconnect_diagnostic_logs)}",
          "obs_connected: #{status.obs_connected || false}",
          "reconnecting: #{status.reconnecting || false}",
          "last_connected_at: #{text(status.last_connected_at)}",
          "last_disconnected_at: #{text(status.last_disconnected_at)}",
          "last_reconnect_attempt_at: #{text(status.last_reconnect_attempt_at)}",
          "last_connection_failed_at: #{text(status.last_connection_failed_at)}",
          "last_error: #{text(status.last_error)}",
        ].join('\n')
      end

      def record_status(result : JSON::Any) : String
        status = IPC::RecordStatusCodec.decode(result)
        [
          # A dash is this surface's word for "OBS has not said yet"; the
          # daemon's own one-line summary words the same case differently.
          "recording: #{status.state("-")}",
          "timecode: #{text(status.timecode)}",
          "duration_ms: #{text(status.duration_ms)}",
          "bytes: #{text(status.bytes)}",
        ].join("\n")
      end

      private def connection_line(result : JSON::Any) : String
        if result["connected"]?.try(&.as_bool?)
          "#{@palette.green}● connected#{@palette.reset}"
        else
          "#{@palette.red}○ disconnected#{@palette.reset}"
        end
      end

      private def scene_line(scene : JSON::Any) : String
        return "    #{scene["name"].as_s}" unless scene["active"]?.try(&.as_bool?)

        "  #{@palette.bold}#{@palette.green}▶ #{scene["name"].as_s}#{@palette.reset}"
      end

      private def audio_line(input : JSON::Any) : String
        dim = @palette.dim
        reset = @palette.reset
        name = input["name"].as_s
        bar = volume_bar(input["volume_percent"]?.try(&.as_i?) || 0)

        case input["muted"]?.try(&.as_bool?)
        when nil  then "  #{dim}? #{name} unknown#{reset}"
        when true then "  #{dim}#{@palette.red}✕ #{name}#{reset} #{dim}muted#{reset} #{bar}"
        else           "  #{@palette.green}♪#{reset} #{name} #{bar}"
        end
      end

      private def volume_bar(percent : Int32) : String
        filled = (percent / VOLUME_BAR_SEGMENTS).clamp(0, VOLUME_BAR_SEGMENTS).to_i
        bar = "█" * filled + "░" * (VOLUME_BAR_SEGMENTS - filled)
        "#{@palette.dim}[#{@palette.reset}#{bar}#{@palette.dim}]#{@palette.reset} #{percent}%"
      end

      private def indent(text : String) : String
        text.lines.map { |line| "  #{line}" }.join('\n')
      end

      private def text(value : (String | Int32 | Int64)?) : String
        value.nil? ? "-" : value.to_s
      end
    end
  end
end
