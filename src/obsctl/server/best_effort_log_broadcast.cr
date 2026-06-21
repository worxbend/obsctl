require "json"

module Obsctl
  module Server
    # Bounded best-effort fanout for secondary diagnostic log-topic delivery.
    #
    # Runtime logging is intentionally outside this helper. Callers should write
    # durable diagnostics before offering entries here.
    class BestEffortLogBroadcast
      DEFAULT_CAPACITY = 4

      getter capacity

      def initialize(@broadcast : Proc(JSON::Any, Nil), @capacity : Int32 = DEFAULT_CAPACITY)
        raise ArgumentError.new("capacity must be positive") unless @capacity > 0

        @lock = Mutex.new
        @outstanding = 0
        @dropped_count = 0_u64
      end

      # Offers a diagnostic log-topic entry for asynchronous delivery.
      #
      # Returns `false` without spawning work when the outstanding delivery
      # bound has already been reached.
      def broadcast(entry : JSON::Any) : Bool
        accepted = @lock.synchronize do
          if @outstanding >= @capacity
            @dropped_count += 1
            false
          else
            @outstanding += 1
            true
          end
        end
        return false unless accepted

        spawn(name: "obsctl-best-effort-log-broadcast") do
          begin
            @broadcast.call(entry)
          rescue
          ensure
            @lock.synchronize { @outstanding -= 1 }
          end
        end

        true
      end

      # Number of diagnostic deliveries currently accepted but not finished.
      def outstanding : Int32
        @lock.synchronize { @outstanding }
      end

      # Number of diagnostic entries dropped because the helper was at capacity.
      def dropped_count : UInt64
        @lock.synchronize { @dropped_count }
      end
    end
  end
end
