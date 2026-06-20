require "json"
require "../config/config"
require "../domain/errors"
require "../obs/client"
require "../obs/protocol/event_subscription"
require "../runtime/logger"
require "../runtime/reconnect_policy"
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

      private class ReconnectWakeSignal
        def initialize
          @wake = Channel(Nil).new
        end

        def wait(delay : Time::Span) : Nil
          select
          when @wake.receive
          when timeout(delay)
          end
        end

        def wake : Nil
          select
          when @wake.send(nil)
          else
          end
        end
      end

      # Creates a supervisor that updates server state and optional event/log broadcasts.
      def initialize(
        @config : Config::Config,
        @state : StateStore,
        @event_broadcast : Proc(JSON::Any, Nil)? = nil,
        @log_broadcast : Proc(JSON::Any, Nil)? = nil,
      )
        @client = nil.as(OBS::Client?)
        @client_lock = Mutex.new
        @lifecycle_lock = Mutex.new
        @lifecycle_state = LifecycleState::Stopped
        @lifecycle_generation = 0_u64
        @reconnect_wake = nil.as(ReconnectWakeSignal?)
      end

      # Returns true while the supervisor loop is starting or can still act.
      def alive? : Bool
        @lifecycle_lock.synchronize { @lifecycle_state != LifecycleState::Stopped }
      end

      # Starts the reconnecting supervisor loop in a background fiber.
      def start : Nil
        generation, wake_signal = @lifecycle_lock.synchronize do
          return unless @lifecycle_state == LifecycleState::Stopped

          @lifecycle_generation += 1
          @lifecycle_state = LifecycleState::Starting
          @reconnect_wake = ReconnectWakeSignal.new
          {@lifecycle_generation, @reconnect_wake.not_nil!}
        end
        spawn(name: "obsctl-obs-supervisor") { run(generation, wake_signal) }
      end

      # Stops reconnect attempts and closes the active OBS client.
      def stop : Nil
        wake_signal = @lifecycle_lock.synchronize do
          @lifecycle_generation += 1
          @lifecycle_state = LifecycleState::Stopped
          signal = @reconnect_wake
          @reconnect_wake = nil
          signal
        end
        wake_signal.try(&.wake)
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
        wake_signal = @lifecycle_lock.synchronize do
          return false if @lifecycle_state == LifecycleState::Stopped

          @reconnect_wake
        end

        client = @client_lock.synchronize do
          existing = @client
          @client = nil
          existing
        end
        @state.mark_disconnected("OBS reconnect requested", reconnecting: true, connection_failed: false)
        publish_log("info", "obs_reconnect_requested", "OBS reconnect requested")
        client.try(&.close)
        wake_signal.try(&.wake)
        true
      end

      private def run(generation : UInt64, wake_signal : ReconnectWakeSignal) : Nil
        return unless mark_running(generation)

        policy = Runtime::ReconnectPolicy.new(@config.reconnect)
        attempt = 0

        until stopped?(generation)
          client = OBS::Client.new(@config, event_subscriptions: OBS::Protocol::EventSubscription::SERVER_DEFAULT)
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
            wait_for_reconnect_delay(policy.delay_for(attempt), wake_signal)
            attempt += 1
          rescue ex
            break if stopped?(generation)

            message = public_message(ex.message, "OBS supervisor failed")
            @state.mark_disconnected(message, reconnecting: @config.reconnect.enabled)
            publish_log("error", "obs_supervisor_error", message)
            client.close if connected
            @client_lock.synchronize { @client = nil if @client == client }
            break if stopped?(generation) || !@config.reconnect.enabled
            wait_for_reconnect_delay(policy.delay_for(attempt), wake_signal)
            attempt += 1
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
          @reconnect_wake = nil
        end
      end

      private def wait_for_reconnect_delay(delay : Time::Span, wake_signal : ReconnectWakeSignal) : Nil
        wake_signal.wait(delay)
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
        @log_broadcast.try(&.call(JSON.parse({
          level:      level,
          code:       code,
          message:    Runtime::Logger.redact_secrets(message),
          created_at: Time.utc.to_rfc3339,
        }.to_json)))
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
