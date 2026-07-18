require "json"

module Obsctl
  module OBS
    module State
      record ObsStats,
        cpu_usage_percent : Float64 = 0.0,
        memory_usage_mb : Float64 = 0.0,
        available_disk_space_mb : Float64 = 0.0,
        active_fps : Float64 = 0.0,
        average_frame_render_time_ms : Float64 = 0.0,
        render_skipped_frames : Int64 = 0_i64,
        render_total_frames : Int64 = 0_i64,
        output_skipped_frames : Int64 = 0_i64,
        output_total_frames : Int64 = 0_i64 do
        def self.from_response(data : JSON::Any) : self
          new(
            cpu_usage_percent: number(data, "cpuUsage"),
            memory_usage_mb: number(data, "memoryUsage"),
            available_disk_space_mb: number(data, "availableDiskSpace"),
            active_fps: number(data, "activeFps"),
            average_frame_render_time_ms: number(data, "averageFrameRenderTime"),
            render_skipped_frames: integer(data, "renderSkippedFrames"),
            render_total_frames: integer(data, "renderTotalFrames"),
            output_skipped_frames: integer(data, "outputSkippedFrames"),
            output_total_frames: integer(data, "outputTotalFrames")
          )
        end

        private def self.number(data, key)
          value = data[key]?
          value.try(&.as_f?) || value.try(&.as_i?).try(&.to_f64) || 0.0
        end

        private def self.integer(data, key)
          data[key]?.try(&.as_i64?) || 0_i64
        end
      end
    end
  end
end
