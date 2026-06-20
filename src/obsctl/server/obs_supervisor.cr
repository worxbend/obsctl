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
        @alive = false
        @stopped = false
      end

      # Returns true while the supervisor loop fiber is running.
      def alive? : Bool
        @lifecycle_lock.synchronize { @alive }
      end

      # Starts the reconnecting supervisor loop in a background fiber.
      def start : Nil
        @lifecycle_lock.synchronize { @stopped = false }
        spawn(name: "obsctl-obs-supervisor") { run }
      end

      # Stops reconnect attempts and closes the active OBS client.
      def stop : Nil
        @lifecycle_lock.synchronize { @stopped = true }
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
        return false unless alive?

        client = @client_lock.synchronize do
          existing = @client
          @client = nil
          existing
        end
        @state.mark_disconnected("OBS reconnect requested", reconnecting: true, connection_failed: false)
        publish_log("info", "obs_reconnect_requested", "OBS reconnect requested")
        client.try(&.close)
        true
      end

      private def run : Nil
        mark_alive(true)
        policy = Runtime::ReconnectPolicy.new(@config.reconnect)
        attempt = 0

        until stopped?
          client = OBS::Client.new(@config, event_subscriptions: OBS::Protocol::EventSubscription::SERVER_DEFAULT)
          connected = false
          begin
            @state.mark_reconnect_attempt
            client.connect
            connected = true
            @client_lock.synchronize { @client = client }
            @state.mark_connected(client.snapshot)
            publish_log("info", "obs_connected", "Connected to OBS WebSocket")
            attempt = 0

            disconnect_error = wait_for_disconnect(client)
            next if client_detached?(client)
            raise disconnect_error || Domain::ConnectionFailed.new("OBS WebSocket disconnected") unless stopped?
          rescue ex : Domain::ObsctlError
            message = public_message(ex.message, "OBS unavailable")
            @state.mark_disconnected(message, reconnecting: @config.reconnect.enabled)
            publish_log("warn", disconnect_log_code(message), message)
            client.close if connected
            @client_lock.synchronize { @client = nil if @client == client }
            break unless @config.reconnect.enabled
            sleep policy.delay_for(attempt)
            attempt += 1
          rescue ex
            message = public_message(ex.message, "OBS supervisor failed")
            @state.mark_disconnected(message, reconnecting: @config.reconnect.enabled)
            publish_log("error", "obs_supervisor_error", message)
            client.close if connected
            @client_lock.synchronize { @client = nil if @client == client }
            break unless @config.reconnect.enabled
            sleep policy.delay_for(attempt)
            attempt += 1
          end
        end
      ensure
        mark_alive(false)
      end

      private def wait_for_disconnect(client : OBS::Client) : Domain::ConnectionFailed?
        until stopped? || !client.connected?
          drain_events(client)
          return client.terminal_error if client.terminal_error
          sleep 250.milliseconds
        end

        client.terminal_error
      end

      private def stopped? : Bool
        @lifecycle_lock.synchronize { @stopped }
      end

      private def mark_alive(value : Bool) : Nil
        @lifecycle_lock.synchronize { @alive = value }
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
