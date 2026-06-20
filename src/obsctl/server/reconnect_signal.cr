module Obsctl
  module Server
    # Internal synchronization primitive for supervisor reconnect sleeps.
    class ReconnectSignal
      def initialize
        @lock = Mutex.new
        @request_epoch = 0_u64
        @cancelled = false
        @waiters = [] of Channel(Nil)
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

      def wait(delay : Time::Span, handled_request_epoch : UInt64) : UInt64
        waiter = Channel(Nil).new(1)

        @lock.synchronize do
          current_epoch = @request_epoch
          return current_epoch if current_epoch > handled_request_epoch
          return handled_request_epoch if @cancelled

          @waiters << waiter
        end

        begin
          select
          when waiter.receive
          when timeout(delay)
          end
        ensure
          @lock.synchronize { @waiters.delete(waiter) }
        end

        current_epoch = latest_request_epoch
        current_epoch > handled_request_epoch ? current_epoch : handled_request_epoch
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
