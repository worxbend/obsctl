require "json"
require "../config/config"
require "../domain/errors"
require "../obs/client"
require "../obs/protocol/event_subscription"
require "../runtime/reconnect_policy"
require "./state_store"

module Obsctl
  module Server
    class ObsSupervisor
      def initialize(
        @config : Config::Config,
        @state : StateStore,
        @event_broadcast : Proc(JSON::Any, Nil)? = nil,
        @log_broadcast : Proc(JSON::Any, Nil)? = nil,
      )
        @client = nil.as(OBS::Client?)
        @client_lock = Mutex.new
        @stopped = false
      end

      def start : Nil
        spawn(name: "obsctl-obs-supervisor") { run }
      end

      def stop : Nil
        @stopped = true
        current_client = @client_lock.synchronize do
          existing = @client
          @client = nil
          existing
        end
        current_client.try(&.close)
      end

      def with_client(&block : OBS::Client -> T) : T forall T
        client = @client_lock.synchronize { @client }
        raise Domain::ObsUnavailable.new unless client && client.connected?
        block.call(client)
      end

      private def run : Nil
        policy = Runtime::ReconnectPolicy.new(@config.connection.reconnect)
        attempt = 0

        until @stopped
          client = OBS::Client.new(@config, event_subscriptions: OBS::Protocol::EventSubscription::SERVER_DEFAULT)
          connected = false
          begin
            client.connect
            connected = true
            @client_lock.synchronize { @client = client }
            @state.update(client.snapshot)
            publish_log("info", "obs_connected", "Connected to OBS WebSocket")
            attempt = 0

            wait_for_disconnect(client)
            raise Domain::ConnectionFailed.new("OBS WebSocket closed") unless @stopped
          rescue ex : Domain::ObsctlError
            @state.mark_disconnected(ex.message)
            publish_log("warn", "obs_disconnected", ex.message || "OBS unavailable")
            client.close if connected
            @client_lock.synchronize { @client = nil if @client == client }
            break unless @config.connection.reconnect.enabled
            sleep policy.delay_for(attempt)
            attempt += 1
          rescue ex
            @state.mark_disconnected(ex.message)
            publish_log("error", "obs_supervisor_error", ex.message || "OBS supervisor failed")
            client.close if connected
            @client_lock.synchronize { @client = nil if @client == client }
            break unless @config.connection.reconnect.enabled
            sleep policy.delay_for(attempt)
            attempt += 1
          end
        end
      end

      private def wait_for_disconnect(client : OBS::Client) : Nil
        until @stopped || !client.connected?
          drain_events(client)
          sleep 250.milliseconds
        end
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
        @state.mark_disconnected(ex.message)
        publish_log("warn", "obs_event_refresh_failed", ex.message || "failed to refresh OBS state after event")
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
          message:    message,
          created_at: Time.utc.to_rfc3339,
        }.to_json)))
      end
    end
  end
end
