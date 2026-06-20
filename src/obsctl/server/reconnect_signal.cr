module Obsctl
  module Server
    # Internal synchronization primitive for supervisor reconnect sleeps.
    class ReconnectSignal
      # Result type returned by `#wait`, distinguishing how the wait ended.
      abstract struct WaitResult
        # The current request epoch at the time of return.
        getter epoch : UInt64

        def initialize(@epoch : UInt64)
        end

        # A durable explicit reconnect request was consumed.
        # The supervisor should retry the OBS connection immediately without
        # incrementing the backoff counter. Only explicit `#request` calls
        # produce this variant — internal wakes and cancel wakes never do.
        struct Requested < WaitResult
        end

        # A transient internal wake or cancel interrupt occurred without
        # advancing the explicit reconnect epoch. The supervisor should follow
        # the normal backoff path. A cancel wake also sets the stopped lifecycle
        # state, so the retry loop will exit at the next `stopped?` check.
        struct Interrupted < WaitResult
        end

        # The wait duration elapsed with no signal.
        # The supervisor should follow the normal backoff path.
        struct TimedOut < WaitResult
        end
      end

      # Test-only hook called under the lock after a waiter is registered.
      # Nil in production; set in specs to synchronize request-during-wait tests.
      property on_waiter_registered : Proc(Nil)?

      def initialize
        @lock = Mutex.new
        @request_epoch = 0_u64
        @cancelled = false
        @waiters = [] of Channel(Nil)
        @on_waiter_registered = nil
      end

      def latest_request_epoch : UInt64
        @lock.synchronize { @request_epoch }
      end

      def request : UInt64
        epoch, waiters = @lock.synchronize do
          @request_epoch += 1
          {@request_epoch, @waiters.dup}
        end
        notify(waiters)
        epoch
      end

      def wait(delay : Time::Span, handled_request_epoch : UInt64) : WaitResult
        waiter = Channel(Nil).new(1)

        @lock.synchronize do
          current_epoch = @request_epoch
          if current_epoch > handled_request_epoch
            return WaitResult::Requested.new(current_epoch)
          end
          if @cancelled
            return WaitResult::Interrupted.new(handled_request_epoch)
          end

          @waiters << waiter
          @on_waiter_registered.try(&.call)
        end

        timed_out = false
        cancelled = false
        current_epoch = handled_request_epoch
        begin
          select
          when waiter.receive
          when timeout(delay)
            timed_out = true
          end
        ensure
          @lock.synchronize do
            @waiters.delete(waiter)
            cancelled = @cancelled
            current_epoch = @request_epoch
          end
        end

        if current_epoch > handled_request_epoch
          WaitResult::Requested.new(current_epoch)
        elsif cancelled
          WaitResult::Interrupted.new(current_epoch)
        elsif timed_out
          WaitResult::TimedOut.new(current_epoch)
        else
          WaitResult::Interrupted.new(current_epoch)
        end
      end

      def wake : Nil
        waiters = @lock.synchronize { @waiters.dup }
        notify(waiters)
      end

      def cancel : Nil
        waiters = @lock.synchronize do
          @cancelled = true
          @waiters.dup
        end
        notify(waiters)
      end

      private def notify(waiters : Array(Channel(Nil))) : Nil
        waiters.each do |waiter|
          select
          when waiter.send(nil)
          else
          end
        end
      end
    end
  end
end
