require "../config/config"
require "../domain/errors"
require "../obs/client"
require "../runtime/reconnect_policy"
require "./state_store"

module Obsctl
  module Server
    class ObsSupervisor
      def initialize(@config : Config::Config, @state : StateStore)
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
        raise Domain::ObsUnavailable.new unless client
        block.call(client)
      end

      private def run : Nil
        policy = Runtime::ReconnectPolicy.new(@config.connection.reconnect)
        attempt = 0

        until @stopped
          client = OBS::Client.new(@config)
          connected = false
          begin
            client.connect
            connected = true
            @client_lock.synchronize { @client = client }
            @state.update(client.snapshot)
            attempt = 0

            until @stopped
              sleep 1.second
            end
          rescue ex : Domain::ObsctlError
            @state.mark_disconnected(ex.message)
            client.close if connected
            @client_lock.synchronize { @client = nil if @client == client }
            break unless @config.connection.reconnect.enabled
            sleep policy.delay_for(attempt)
            attempt += 1
          rescue ex
            @state.mark_disconnected(ex.message)
            client.close if connected
            @client_lock.synchronize { @client = nil if @client == client }
            break unless @config.connection.reconnect.enabled
            sleep policy.delay_for(attempt)
            attempt += 1
          end
        end
      end
    end
  end
end
