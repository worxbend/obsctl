require "json"
require "../domain/errors"
require "../ipc/protocol"

module Obsctl
  module CLI
    # Streams daemon events to stdout as newline-delimited JSON.
    #
    # `watch` is the scripting counterpart to the TUI: it subscribes to the same
    # daemon topics and writes one self-describing JSON object per line, so a
    # consumer can pipe it into `jq` or read it line-by-line without framing
    # logic. Each line is flushed immediately; a buffered stream would make the
    # command useless for reacting to events as they happen.
    class Watcher
      TOPICS         = ["state", "events", "logs"]
      SUBSCRIBE_ID   = "watch-subscribe"
      DEFAULT_TOPICS = TOPICS

      alias SessionFactory = Proc(String, Array(String), IPC::ClientSession)

      def initialize(
        @socket_path : String,
        @topics : Array(String) = DEFAULT_TOPICS,
        @stdout : IO = STDOUT,
        @limit : Int32? = nil,
        @session_factory : SessionFactory = ->Watcher.subscribe(String, Array(String)),
      )
      end

      # Validates topic names against the set the daemon publishes.
      def self.validate_topics!(topics : Array(String)) : Array(String)
        raise Domain::CommandParseError.new("no topics selected") if topics.empty?

        unknown = topics.reject { |topic| TOPICS.includes?(topic) }
        unless unknown.empty?
          raise Domain::CommandParseError.new("unknown watch topic: #{unknown.join(", ")}; expected #{TOPICS.join(", ")}")
        end

        topics.uniq!
      end

      # Opens a subscription session for the requested topics.
      def self.subscribe(socket_path : String, topics : Array(String)) : IPC::ClientSession
        session = IPC::UnixClient.new(socket_path).connect
        request = IPC::Request.new(SUBSCRIBE_ID, IPC::Request::TYPE_SUBSCRIBE, topics: topics)
        session.write_message(request)
        response = session.read_message.as?(IPC::Response)
        unless response && response.id == request.id && response.ok
          session.close
          raise Domain::IpcProtocolError.new("server rejected watch subscription")
        end
        session
      rescue ex : Domain::IpcConnectionFailed
        raise Domain::ServerUnavailable.new(ex.message)
      end

      # Streams until the daemon closes the connection or the limit is reached.
      def run : Int32
        session = @session_factory.call(@socket_path, @topics)
        emitted = 0

        begin
          loop do
            message = session.read_message
            break unless message

            event = message.as?(IPC::Event)
            next unless event
            # The daemon fans out by subscription, but a topic filter is
            # cheaper to honor here than to renegotiate, and it keeps the
            # output faithful to what the user asked for.
            next unless @topics.includes?(event.topic)

            @stdout.puts(line_for(event))
            @stdout.flush
            emitted += 1

            if limit = @limit
              break if emitted >= limit
            end
          end
        ensure
          session.close
        end

        Domain::ExitCode::Success.value
      end

      # One flat object per event; `data` is null when the event carries none.
      private def line_for(event : IPC::Event) : String
        JSON.build do |json|
          json.object do
            json.field "topic", event.topic
            json.field "data" do
              if data = event.data
                data.to_json(json)
              else
                json.null
              end
            end
          end
        end
      end
    end
  end
end
