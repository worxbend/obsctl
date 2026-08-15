require "../ipc/client_session"
require "../ipc/event"
require "../domain/errors"

module Obsctl
  module Server
    # Tracks IPC clients subscribed to pushed state, event, and log topics.
    class ClientRegistry
      ALLOWED_TOPICS = Set{"state", "events", "logs"}

      # How long a single broadcast write may block before the subscriber is
      # treated as dead and dropped.
      #
      # `broadcast` runs on the caller's fiber, and its callers are the ones
      # that matter: the OBS supervisor fiber (which also drains OBS events,
      # polls telemetry and drives reconnect) and the IPC handler fibers.
      # Without a bound, one subscriber that stops reading — `obsctl watch`
      # piped into a pager nobody is paging, a stopped TUI — fills its socket
      # buffer and parks whichever fiber is broadcasting, taking the daemon
      # down for every other client. Two seconds is far longer than a healthy
      # local Unix-socket write and far shorter than a human notices.
      BROADCAST_WRITE_TIMEOUT = 2.seconds

      # A registered client session and its requested topic set.
      record Subscription, session : IPC::ClientSession, topics : Set(String)

      # Creates an empty registry.
      def initialize
        @subscriptions = {} of UInt64 => Subscription
        @lock = Mutex.new
      end

      # Adds or replaces a subscription for a connected client session.
      def add(session : IPC::ClientSession, topics : Array(String)) : Nil
        topic_set = validate_topics(topics)
        session.write_timeout = BROADCAST_WRITE_TIMEOUT
        @lock.synchronize do
          @subscriptions[session.object_id] = Subscription.new(session, topic_set)
        end
      end

      # Removes a client session from the registry.
      def remove(session : IPC::ClientSession) : Nil
        @lock.synchronize do
          @subscriptions.delete(session.object_id)
        end
      end

      # Returns the current number of registered client sessions.
      def client_count : Int32
        @lock.synchronize { @subscriptions.size.to_i32 }
      end

      # Broadcasts a topic event to all matching subscribers.
      def broadcast(topic : String, data : JSON::Any? = nil) : Nil
        event = IPC::Event.new(topic, data)
        dead_sessions = [] of IPC::ClientSession

        subscriptions_for(topic).each do |subscription|
          subscription.session.write_message(event)
        rescue IO::Error
          # Covers both a closed peer and `IO::TimeoutError` from a peer that
          # stopped reading. A timed-out write may have left a partial line on
          # the wire, so the session cannot be reused either way — drop it and
          # close it so the client notices rather than reading a truncated
          # stream.
          dead_sessions << subscription.session
        end

        dead_sessions.each do |session|
          remove(session)
          session.close rescue nil
        end
      end

      private def validate_topics(topics : Array(String)) : Set(String)
        raise Domain::IpcProtocolError.new("subscribe request must include at least one topic") if topics.empty?

        topic_set = Set(String).new
        topics.each do |topic|
          unless ALLOWED_TOPICS.includes?(topic)
            raise Domain::IpcProtocolError.new("unsupported subscribe topic: #{topic}")
          end
          topic_set << topic
        end
        topic_set
      end

      private def subscriptions_for(topic : String) : Array(Subscription)
        @lock.synchronize do
          @subscriptions.values.select(&.topics.includes?(topic))
        end
      end
    end
  end
end
