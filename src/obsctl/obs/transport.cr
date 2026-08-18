require "http/web_socket"
require "json"
require "./auth"
require "./connection"
require "./protocol/request_id"
require "./protocol/request"
require "./protocol/response"
require "./protocol/event"
require "./protocol/message"
require "../config/config"
require "../domain/errors"

module Obsctl
  module OBS
    # The obs-websocket connection itself: socket, handshake, frame routing,
    # request correlation, and how a session ends.
    #
    # Split out of `Client`, which was both this and the 25-method façade over
    # OBS operations. The two change for unrelated reasons — this one when the
    # transport or the 5.x handshake changes, the façade when obsctl needs
    # another OBS operation — and only this half is intricate concurrent code.
    # `Client` owns one of these and forwards to it; nothing else does.
    class Transport
      # How many OBS events may wait for the supervisor to drain them.
      #
      # Sized for a burst: with volume meters subscribed OBS emits tens of
      # events a second, and the supervisor drains between its own 100ms
      # disconnect checks. Deep enough that a normal burst never overflows,
      # shallow enough that a stalled consumer cannot grow it without bound.
      EVENT_BUFFER_SIZE = 256

      def initialize(
        @config : Config::Config,
        @event_subscriptions : Int32? = nil,
      )
        @request_ids = Protocol::RequestId.new
        @identified = false
        @ws = nil.as(HTTP::WebSocket?)
        @system_frames = Channel(String | Exception).new(8)
        # Buffered, so `handle_frame` can hand off an event without waiting for
        # the supervisor to be at the receiving end. It used to spawn a fiber
        # per event onto an unbuffered channel, which leaked a parked fiber for
        # every event that arrived once nobody was draining any more, and let
        # two updates for the same input be applied out of order.
        @events = Channel(Protocol::Event).new(EVENT_BUFFER_SIZE)
        @pending = {} of String => Channel(Protocol::Response | Exception)
        @pending_lock = Mutex.new
        @terminal_error = nil.as(Domain::ConnectionFailed?)
        @terminal_error_lock = Mutex.new
        @close_notifications = Channel(Domain::ConnectionFailed).new(1)
        @close_requested = false
      end

      getter events

      # Returns true after Identify completes and the underlying socket is open.
      def connected? : Bool
        ws = @ws
        return false unless ws

        @identified && !ws.closed?
      end

      # Returns the safe terminal connection error that closed this client.
      def terminal_error : Domain::ConnectionFailed?
        @terminal_error_lock.synchronize { @terminal_error }
      end

      # Waits for the WebSocket reader to observe a terminal close or protocol
      # error, returning the same sanitized error exposed by `terminal_error`.
      def wait_for_close(timeout : Time::Span) : Domain::ConnectionFailed?
        notifications = @terminal_error_lock.synchronize do
          return @terminal_error if @terminal_error
          @close_notifications
        end

        select
        when error = notifications.receive
          error
        when timeout(timeout)
          terminal_error
        end
      end

      # Opens the WebSocket, performs Hello/Identify/Identified, and starts the

      def connect : Nil
        reset_terminal_state
        ws = Connection.new(@config.connection).connect
        # Assigned before anything can fail after it. From here on the socket
        # owns an fd and a reader fiber, so `close` has to run even if the
        # Identify below is rejected — a non-nil `@ws` is exactly that fact,
        # which is why it replaced the separate `@socket_open` flag it used to
        # be tracked by.
        @ws = ws
        ws.on_message { |message| handle_frame(message) }
        ws.on_close do |code, reason|
          fail_all_pending(close_terminal_error(code, reason))
        end
        spawn do
          ws.run
        rescue
          fail_all_pending(record_terminal_error(Domain::ConnectionFailed.new("OBS WebSocket reader failed")))
        end
        hello = read_system_frame
        identify(hello)
        @identified = true
      end

      # Returns true once `connect` has opened the socket, whether or not the
      # Hello/Identify handshake that follows it succeeded.
      def socket_open? : Bool
        !@ws.nil?
      end

      # Closes the WebSocket and marks this client as no longer identified.
      #
      # Safe to call on a client that never connected, and safe to call twice.
      def close : Nil
        @terminal_error_lock.synchronize { @close_requested = true }
        @identified = false
        ws = @ws
        return unless ws

        ws.close unless ws.closed?
      rescue
      end

      # Sends a typed obs-websocket request frame and waits for the matching
      # request ID response or timeout.
      def request(request_type : String, data : JSON::Any? = nil) : Protocol::Response
        raise Domain::ConnectionFailed.new("OBS client is not identified") unless @identified
        id = @request_ids.next
        responses = Channel(Protocol::Response | Exception).new(1)
        @pending_lock.synchronize { @pending[id] = responses }
        begin
          connected_socket.send(Protocol::Request.new(request_type, id, data).to_frame)
        rescue ex
          raise Domain::ConnectionFailed.new("failed to send OBS request #{request_type}: #{ex.message}")
        end
        timeout = @config.connection.request_timeout_ms.milliseconds
        select
        when result = responses.receive
          raise result if result.is_a?(Exception)
          response = result
          unless response.request_status.result
            raise Domain::ObsRequestFailed.new(request_type, response.request_status.comment || "request returned failure")
          end
          response
        when timeout(timeout)
          raise Domain::RequestTimeout.new(request_type)
        end
      ensure
        @pending_lock.synchronize { @pending.delete(id) } if id
      end

      private def identify(hello_frame : String) : Nil
        hello = JSON.parse(hello_frame)
        raise Domain::ConnectionFailed.new("expected OBS Hello frame") unless hello["op"].as_i == 0
        data = hello["d"]
        identify_data = {} of String => JSON::Any
        identify_data["rpcVersion"] = JSON::Any.new(data["rpcVersion"].as_i64)
        if event_subscriptions = @event_subscriptions
          identify_data["eventSubscriptions"] = JSON::Any.new(event_subscriptions.to_i64)
        end

        if auth = data["authentication"]?
          password = password_from_config
          salt = auth["salt"].as_s
          challenge = auth["challenge"].as_s
          identify_data["authentication"] = JSON::Any.new(Auth.authentication(password, salt, challenge))
        end

        frame = JSON.build do |json|
          json.object do
            json.field "op", 1
            json.field "d", identify_data
          end
        end
        connected_socket.send(frame)
        identified = read_system_frame
        parsed = JSON.parse(identified)
        raise Domain::AuthenticationFailed.new unless parsed["op"].as_i == 2
      end

      private def password_from_config : String
        if env_name = @config.connection.password_env
          if value = ENV[env_name]?
            return value unless value.empty?
          end
        end
        @config.connection.password || ""
      end

      private def read_system_frame : String
        timeout = @config.connection.request_timeout_ms.milliseconds
        select
        when result = @system_frames.receive
          raise result if result.is_a?(Exception)
          result
        when timeout(timeout)
          raise Domain::ConnectionFailed.new("timed out waiting for OBS WebSocket")
        end
      end

      # The open socket, for the paths that cannot proceed without one.
      #
      # `connect` assigns `@ws` before the handshake, so anything reachable
      # after that point has a socket; this turns "should never be nil" into a
      # checked error rather than an assumption.
      private def connected_socket : HTTP::WebSocket
        @ws || raise Domain::ConnectionFailed.new("OBS WebSocket is not open")
      end

      private def number(data : JSON::Any, key : String) : Float64?
        value = data[key]?
        return unless value
        value.as_f? || value.as_i?.try(&.to_f64)
      end

      # Hands an event to the supervisor without blocking the reader fiber.
      #
      # This runs on the single fiber that reads the WebSocket, so it must
      # never park: blocking here stops request responses being routed too.
      # A full buffer means the supervisor is behind, and the useful thing to
      # do with a burst of stale volume meters is drop it — daemon state is
      # reconciled by the telemetry poll every two seconds regardless.
      private def queue_event(event : Protocol::Event) : Nil
        select
        when @events.send(event)
          # Queued.
        else
          # Buffer full; drop rather than stall the reader.
        end
      end

      private def handle_frame(frame : String) : Nil
        opcode = Protocol::Message.opcode(frame)
        begin
          case opcode
          when 7
            route_response(frame)
          when 5
            if event = Protocol::Event.from_frame(frame)
              queue_event(event)
            end
          else
            @system_frames.send(frame)
          end
        rescue
          if opcode == 7
            fail_response_parser_error
          else
            fail_malformed_frame
          end
        end
      rescue
        fail_malformed_frame
      end

      private def route_response(frame : String) : Nil
        response = Protocol::Response.from_frame(frame)
        return unless response

        channel = @pending_lock.synchronize { @pending[response.request_id]? }
        send_pending(channel, response) if channel
      rescue
        fail_response_parser_error
      end

      private def fail_malformed_frame : Nil
        fail_protocol_error(
          "OBS WebSocket protocol error: malformed OBS frame",
          Domain::DisconnectKind::MalformedFrame
        )
      end

      private def fail_response_parser_error : Nil
        fail_protocol_error(
          "OBS WebSocket protocol error: response parser error",
          Domain::DisconnectKind::ResponseParserError
        )
      end

      private def fail_protocol_error(message : String, kind : Domain::DisconnectKind) : Nil
        fail_all_pending(record_terminal_error(Domain::ConnectionFailed.new(message, kind)))
        close_after_protocol_error
      end

      private def fail_all_pending(error : Exception) : Nil
        @identified = false
        pending = @pending_lock.synchronize do
          channels = @pending.values.to_a
          @pending.clear
          channels
        end
        pending.each { |channel| fail_pending(channel, error) }
        send_system_error(error)
      end

      private def send_pending(channel : Channel(Protocol::Response | Exception), value : Protocol::Response | Exception) : Nil
        select
        when channel.send(value)
        else
        end
      end

      private def fail_pending(channel : Channel(Protocol::Response | Exception), error : Exception) : Nil
        select
        when channel.receive
        else
        end
        send_pending(channel, error)
      end

      private def send_system_error(error : Exception) : Nil
        select
        when @system_frames.send(error)
        else
        end
      end

      private def reset_terminal_state : Nil
        @terminal_error_lock.synchronize do
          @terminal_error = nil
          @close_notifications = Channel(Domain::ConnectionFailed).new(1)
          @close_requested = false
        end
      end

      private def close_terminal_error(
        code : HTTP::WebSocket::CloseCode? = nil,
        reason : String = "",
      ) : Domain::ConnectionFailed
        existing = terminal_error
        return existing if existing

        message, kind = @terminal_error_lock.synchronize do
          if @close_requested
            {"OBS WebSocket closed cleanly", Domain::DisconnectKind::ClosedCleanly}
          elsif code
            {websocket_close_message(code, reason), Domain::DisconnectKind::Disconnected}
          else
            {"OBS WebSocket disconnected", Domain::DisconnectKind::Disconnected}
          end
        end
        record_terminal_error(Domain::ConnectionFailed.new(message, kind))
      end

      private def websocket_close_message(code : HTTP::WebSocket::CloseCode, reason : String) : String
        explanation = case code.value
                      when 1000 then "normal closure requested by OBS"
                      when 1001 then "OBS is going away or shutting down"
                      when 1002 then "WebSocket protocol error"
                      when 1005 then "OBS closed without a close status"
                      when 1006 then "connection ended without a close frame"
                      when 1011 then "OBS encountered an internal error"
                      when 1012 then "OBS is restarting"
                      when 1013 then "OBS asked the client to retry later"
                      when 4000 then "OBS reported an unknown reason"
                      when 4001 then "OBS could not decode a client message"
                      when 4002 then "OBS received an unknown message type"
                      when 4003 then "client sent a request before Identify completed"
                      when 4004 then "client attempted to Identify more than once"
                      when 4005 then "OBS authentication failed"
                      when 4006 then "OBS does not support the requested RPC version"
                      when 4007 then "OBS invalidated the session"
                      when 4008 then "OBS does not support a requested feature"
                      when 4009 then "an OBS request was missing its request type"
                      else           "peer closed the WebSocket"
                      end
        suffix = reason.empty? ? explanation : "#{explanation}; reason: #{reason}"
        "OBS WebSocket disconnected (close code #{code.value}: #{suffix})"
      end

      private def record_terminal_error(error : Domain::ConnectionFailed) : Domain::ConnectionFailed
        terminal, notifications = @terminal_error_lock.synchronize do
          if existing = @terminal_error
            {existing, nil.as(Channel(Domain::ConnectionFailed)?)}
          else
            @terminal_error = error
            {error, @close_notifications}
          end
        end
        notify_close(notifications, terminal) if notifications
        terminal
      end

      private def notify_close(notifications : Channel(Domain::ConnectionFailed), error : Domain::ConnectionFailed) : Nil
        select
        when notifications.send(error)
        else
        end
      end

      private def close_after_protocol_error : Nil
        ws = @ws
        return if ws.nil? || ws.closed?

        spawn(name: "obs-protocol-error-close") do
          ws.close unless ws.closed?
        rescue
        end
      end
    end
  end
end
