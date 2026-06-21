require "json"
require "../config/config"
require "../domain/errors"
require "../obs/client"
require "../obs/protocol/event_subscription"
require "../runtime/logger"
require "../runtime/reconnect_policy"
require "./reconnect_signal"
require "./state_store"

module Obsctl
  module Server
    # Owns the single OBS WebSocket client and reconnect loop for the daemon.
    class ObsSupervisor
      enum LifecycleState
        Starting
        Running
        Stopped
      end

      private record ReconnectPublication,
        detached_client : OBS::Client?,
        state_payload : JSON::Any,
        log_payload : JSON::Any

      # Creates a supervisor that updates server state and optional event/log broadcasts.
      def initialize(
        @config : Config::Config,
        @state : StateStore,
        @event_broadcast : Proc(JSON::Any, Nil)? = nil,
        @log_broadcast : Proc(JSON::Any, Nil)? = nil,
        @logger : Runtime::Logger? = nil,
      )
        @client = nil.as(OBS::Client?)
        @client_lock = Mutex.new
        @lifecycle_lock = Mutex.new
        @lifecycle_state = LifecycleState::Stopped
        @lifecycle_generation = 0_u64
        @reconnect_signal = nil.as(ReconnectSignal?)
        @stopped_reconnect_attempted = false
        @test_reconnect_before_publication = nil.as(Proc(Nil)?)
      end

      # Test-only observability for reconnect attempts rejected by stopped lifecycle state.
      def stopped_reconnect_attempted? : Bool
        @lifecycle_lock.synchronize { @stopped_reconnect_attempted }
      end

      # Test-only synchronization hook invoked after `reconnect` captures a
      # live generation and before it re-checks that generation for public
      # reconnect publication. The hook runs without supervisor locks held and
      # may block to coordinate deterministic race specs.
      property test_reconnect_before_publication : Proc(Nil)?

      # Returns true while the supervisor loop is starting or can still act.
      def alive? : Bool
        @lifecycle_lock.synchronize { @lifecycle_state != LifecycleState::Stopped }
      end

      # Starts the reconnecting supervisor loop in a background fiber.
      def start : Nil
        generation, reconnect_signal = @lifecycle_lock.synchronize do
          return unless @lifecycle_state == LifecycleState::Stopped

          @lifecycle_generation += 1
          @lifecycle_state = LifecycleState::Starting
          @reconnect_signal = ReconnectSignal.new
          @stopped_reconnect_attempted = false
          {@lifecycle_generation, @reconnect_signal.not_nil!}
        end
        spawn(name: "obsctl-obs-supervisor") { run(generation, reconnect_signal) }
      end

      # Stops reconnect attempts and closes the active OBS client.
      def stop : Nil
        reconnect_signal = @lifecycle_lock.synchronize do
          @lifecycle_generation += 1
          @lifecycle_state = LifecycleState::Stopped
          signal = @reconnect_signal
          @reconnect_signal = nil
          signal
        end
        reconnect_signal.try(&.cancel)
        current_client = @client_lock.synchronize do
          existing = @client
          @client = nil
          existing
        end
        current_client.try(&.close)
      end

      # Yields the active OBS client or raises when OBS is unavailable.
      def with_client(&block : OBS::Client -> T) : T forall T
        client = @client_lock.synchronize { @client }
        raise Domain::ObsUnavailable.new unless client && client.connected?
        block.call(client)
      end

      # Drops the active client so the supervisor reconnect loop starts over.
      def reconnect : Bool
        generation, reconnect_signal = @lifecycle_lock.synchronize do
          if @lifecycle_state == LifecycleState::Stopped
            @stopped_reconnect_attempted = true
            return false
          end

          signal = @reconnect_signal
          return false unless signal

          {@lifecycle_generation, signal}
        end

        @test_reconnect_before_publication.try(&.call)

        publication = @lifecycle_lock.synchronize do
          if @lifecycle_state == LifecycleState::Stopped ||
             @lifecycle_generation != generation ||
             @reconnect_signal != reconnect_signal
            @stopped_reconnect_attempted = true if @lifecycle_state == LifecycleState::Stopped
            nil
          else
            accepted_at = Time.utc
            reconnect_signal.request
            detached_client = @client_lock.synchronize do
              existing = @client
              @client = nil
              existing
            end
            ReconnectPublication.new(
              detached_client,
              @state.mark_reconnect_requested_and_build_payload(accepted_at),
              log_payload("info", "obs_reconnect_requested", "OBS reconnect requested", accepted_at)
            )
          end
        end

        return false unless publication

        publish_reconnect(publication)
        true
      end

      private def run(generation : UInt64, reconnect_signal : ReconnectSignal) : Nil
        return unless mark_running(generation)

        policy = Runtime::ReconnectPolicy.new(@config.reconnect)
        attempt = 0

        until stopped?(generation)
          client = OBS::Client.new(@config, event_subscriptions: OBS::Protocol::EventSubscription::SERVER_DEFAULT)
          handled_request_epoch = reconnect_signal.latest_request_epoch
          connected = false
          begin
            @state.mark_reconnect_attempt
            client.connect
            connected = true
            break unless claim_client(generation, client)

            @state.mark_connected(client.snapshot)
            publish_log("info", "obs_connected", "Connected to OBS WebSocket")
            attempt = 0

            disconnect_error = wait_for_disconnect(generation, client)
            next if client_detached?(client)
            raise disconnect_error || Domain::ConnectionFailed.new("OBS WebSocket disconnected") unless stopped?(generation)
          rescue ex : Domain::ObsctlError
            break if stopped?(generation)

            message = public_message(ex.message, "OBS unavailable")
            @state.mark_disconnected(message, reconnecting: @config.reconnect.enabled)
            publish_log("warn", disconnect_log_code(message), message)
            client.close if connected
            @client_lock.synchronize { @client = nil if @client == client }
            break if stopped?(generation) || !@config.reconnect.enabled
            result = wait_for_reconnect_delay(policy.delay_for(attempt), reconnect_signal, handled_request_epoch)
            case result
            when ReconnectSignal::WaitResult::Requested
              # Explicit reconnect request consumed — retry immediately without incrementing backoff.
            when ReconnectSignal::WaitResult::Cancelled
              break # Stop-initiated cancel; exit the retry loop immediately.
            when ReconnectSignal::WaitResult::TimedOut, ReconnectSignal::WaitResult::Interrupted
              attempt += 1
            end
          rescue ex
            break if stopped?(generation)

            message = public_message(ex.message, "OBS supervisor failed")
            @state.mark_disconnected(message, reconnecting: @config.reconnect.enabled)
            publish_log("error", "obs_supervisor_error", message)
            client.close if connected
            @client_lock.synchronize { @client = nil if @client == client }
            break if stopped?(generation) || !@config.reconnect.enabled
            result = wait_for_reconnect_delay(policy.delay_for(attempt), reconnect_signal, handled_request_epoch)
            case result
            when ReconnectSignal::WaitResult::Requested
              # Explicit reconnect request consumed — retry immediately without incrementing backoff.
            when ReconnectSignal::WaitResult::Cancelled
              break # Stop-initiated cancel; exit the retry loop immediately.
            when ReconnectSignal::WaitResult::TimedOut, ReconnectSignal::WaitResult::Interrupted
              attempt += 1
            end
          end
        end
      ensure
        mark_stopped(generation)
      end

      private def wait_for_disconnect(generation : UInt64, client : OBS::Client) : Domain::ConnectionFailed?
        until stopped?(generation) || !client.connected?
          drain_events(client)
          return client.terminal_error if client.terminal_error
          sleep 250.milliseconds
        end

        client.terminal_error
      end

      private def stopped?(generation : UInt64) : Bool
        @lifecycle_lock.synchronize do
          @lifecycle_state == LifecycleState::Stopped || @lifecycle_generation != generation
        end
      end

      private def claim_client(generation : UInt64, client : OBS::Client) : Bool
        claimed = false
        @lifecycle_lock.synchronize do
          return false if @lifecycle_state == LifecycleState::Stopped || @lifecycle_generation != generation

          @client_lock.synchronize { @client = client }
          claimed = true
        end
        claimed
      ensure
        client.close unless claimed
      end

      private def mark_running(generation : UInt64) : Bool
        @lifecycle_lock.synchronize do
          return false unless @lifecycle_generation == generation
          return false if @lifecycle_state == LifecycleState::Stopped

          @lifecycle_state = LifecycleState::Running
          true
        end
      end

      private def mark_stopped(generation : UInt64) : Nil
        @lifecycle_lock.synchronize do
          next unless @lifecycle_generation == generation

          @lifecycle_state = LifecycleState::Stopped
          @reconnect_signal = nil
        end
      end

      private def wait_for_reconnect_delay(
        delay : Time::Span,
        reconnect_signal : ReconnectSignal,
        handled_request_epoch : UInt64,
      ) : ReconnectSignal::WaitResult
        reconnect_signal.wait(delay, handled_request_epoch)
      end

      private def drain_events(client : OBS::Client) : Nil
        loop do
          select
          when event = client.events.receive
            publish_event(event)
            @state.update(client.snapshot)
          when timeout(0.milliseconds)
            break
          end
        end
      rescue ex : Domain::ObsctlError
        message = public_message(ex.message, "failed to refresh OBS state after event")
        @state.mark_disconnected(message)
        publish_log("warn", "obs_event_refresh_failed", message)
      end

      private def client_detached?(client : OBS::Client) : Bool
        @client_lock.synchronize { @client != client }
      end

      private def publish_event(event : OBS::Protocol::Event) : Nil
        @event_broadcast.try(&.call(JSON.parse({
          event_type: event.event_type,
          event_data: event.event_data,
        }.to_json)))
      end

      private def publish_log(level : String, code : String, message : String) : Nil
        @log_broadcast.try(&.call(log_payload(level, code, message)))
      end

      private def log_payload(level : String, code : String, message : String, at : Time = Time.utc) : JSON::Any
        JSON.parse({
          level:      level,
          code:       code,
          message:    Runtime::Logger.redact_secrets(message),
          created_at: at.to_rfc3339,
        }.to_json)
      end

      private def publish_reconnect(publication : ReconnectPublication) : Nil
        detached_client = publication.detached_client
        detached_client_closed = false
        begin
          detached_client.try do |client|
            client.close
            detached_client_closed = true
          end
          publish_reconnect_state(publication.state_payload)
          publish_reconnect_log(publication.log_payload)
        ensure
          detached_client.try(&.close) unless detached_client_closed
        end
      end

      private def publish_reconnect_state(payload : JSON::Any) : Nil
        @state.publish_snapshot_payload(payload)
      rescue ex
        publish_reconnect_diagnostic(
          "obs_reconnect_state_publication_failed",
          "OBS reconnect state publication failed",
          ex
        )
      end

      private def publish_reconnect_log(payload : JSON::Any) : Nil
        @log_broadcast.try(&.call(payload))
      rescue ex
        publish_reconnect_diagnostic(
          "obs_reconnect_log_publication_failed",
          "OBS reconnect log publication failed",
          ex
        )
      end

      private def publish_reconnect_diagnostic(code : String, message : String, cause : Exception) : Nil
        diagnostic = "#{message}: #{exception_summary(cause)}"
        write_reconnect_diagnostic(code, diagnostic)

        broadcast = @log_broadcast
        return unless broadcast

        spawn(name: "obsctl-reconnect-diagnostic-log") do
          begin
            broadcast.call(log_payload("warn", code, diagnostic))
          rescue ex
            fallback = "#{diagnostic}; diagnostic log publication failed: #{exception_summary(ex)}"
            write_reconnect_diagnostic(code, fallback)
          end
        end
      end

      private def write_reconnect_diagnostic(code : String, message : String) : Nil
        @logger.try(&.warn("#{code} #{Runtime::Logger.redact_secrets(message)}"))
      rescue
      end

      private def exception_summary(ex : Exception) : String
        exception_name = ex.class.name || "Exception"
        message = ex.message
        return exception_name unless message && !message.empty?

        "#{exception_name}: #{Runtime::Logger.redact_secrets(message)}"
      end

      private def public_message(message : String?, fallback : String) : String
        Runtime::Logger.redact_secrets(message || fallback)
      end

      private def disconnect_log_code(message : String) : String
        case message
        when /response parser error/
          "obs_response_parser_error"
        when /malformed OBS frame/
          "obs_malformed_frame"
        when /closed cleanly/
          "obs_closed_cleanly"
        when /disconnected/
          "obs_disconnected"
        else
          "obs_disconnected"
        end
      end
    end
  end
end
