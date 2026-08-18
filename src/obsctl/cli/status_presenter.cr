require "json"
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
    # Everything reads defensively (`try(&.as_s?) || "-"`) because the payload
    # is whatever the daemon sent. A field the running daemon does not publish —
    # an older build, a newer one — renders as a dash rather than crashing the
    # client.
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
        [
          "pid: #{result["pid"]?.try(&.as_i?) || "-"}",
          "uptime_seconds: #{result["uptime_seconds"]?.try(&.as_i?) || "-"}",
          "socket_path: #{result["socket_path"]?.try(&.as_s?) || "-"}",
          "client_count: #{result["client_count"]?.try(&.as_i?) || 0}",
          "dropped_reconnect_diagnostic_logs: #{optional_integer_text(result["dropped_reconnect_diagnostic_logs"]?)}",
          "obs_connected: #{result["obs_connected"]?.try(&.as_bool?) || false}",
          "reconnecting: #{result["reconnecting"]?.try(&.as_bool?) || false}",
          "last_connected_at: #{timestamp_text(result["last_connected_at"]?)}",
          "last_disconnected_at: #{timestamp_text(result["last_disconnected_at"]?)}",
          "last_reconnect_attempt_at: #{timestamp_text(result["last_reconnect_attempt_at"]?)}",
          "last_connection_failed_at: #{timestamp_text(result["last_connection_failed_at"]?)}",
          "last_error: #{result["last_error"]?.try(&.as_s?) || "-"}",
        ].join('\n')
      end

      def record_status(result : JSON::Any) : String
        [
          "recording: #{record_state_label(result)}",
          "timecode: #{result["timecode"]?.try(&.as_s?) || "-"}",
          "duration_ms: #{result["duration_ms"]?.try(&.as_i64?) || "-"}",
          "bytes: #{result["bytes"]?.try(&.as_i64?) || "-"}",
        ].join("\n")
      end

      # Three states, not two: OBS reports "recording" and "paused"
      # independently, and a daemon that has not heard from OBS yet knows
      # neither. A dash says "unknown" rather than claiming "stopped".
      private def record_state_label(result : JSON::Any) : String
        case result["active"]?.try(&.as_bool?)
        when true  then result["paused"]?.try(&.as_bool?) == true ? "paused" : "active"
        when false then "stopped"
        else            "-"
        end
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

      private def timestamp_text(value : JSON::Any?) : String
        value.try(&.as_s?) || "-"
      end

      private def optional_integer_text(value : JSON::Any?) : String
        value.try(&.as_i64?).try(&.to_s) || "-"
      end
    end
  end
end
