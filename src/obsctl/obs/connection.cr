require "http/web_socket"
require "uri"
require "../config/config"
require "../domain/errors"

module Obsctl
  module OBS
    # Opens the raw obs-websocket transport for an OBS connection config.
    class Connection
      getter websocket

      def initialize(@config : Config::ConnectionConfig)
        @websocket = uninitialized HTTP::WebSocket
      end

      # Connects to OBS and converts low-level connection failures into a domain error.
      #
      # Honours `connection.connect_timeout_ms`. A non-positive value means "no
      # timeout" and restores the old behaviour of waiting indefinitely.
      def connect : HTTP::WebSocket
        uri = URI.parse("ws://#{@config.host}:#{@config.port}")
        timeout = @config.connect_timeout_ms
        @websocket = timeout > 0 ? open_with_timeout(uri, timeout.milliseconds) : open(uri)
      rescue ex : Domain::ConnectionFailed
        raise ex
      rescue ex
        raise connection_failed(ex.message)
      end

      private def open(uri : URI) : HTTP::WebSocket
        HTTP::WebSocket.new(uri)
      end

      # Opens the socket on a separate fiber so the caller can give up on it.
      #
      # `HTTP::WebSocket.new` performs the TCP connect and the HTTP upgrade
      # handshake in one blocking call and offers no deadline of its own, so
      # there is nothing to configure — the only way to bound it is to stop
      # waiting for it. A peer that completes the TCP handshake and then never
      # answers the upgrade (a hung OBS, a tunnel to a dead endpoint) would
      # otherwise park the supervisor fiber forever: it never reaches the
      # request timeout, never reports a disconnect, and never retries.
      private def open_with_timeout(uri : URI, timeout : Time::Span) : HTTP::WebSocket
        results = Channel(HTTP::WebSocket | Exception).new(1)
        spawn(name: "obsctl-obs-connect") do
          results.send(HTTP::WebSocket.new(uri))
        rescue ex
          results.send(ex)
        end

        select
        when result = results.receive
          raise result if result.is_a?(Exception)
          result
        when timeout(timeout)
          # The connect fiber is still parked in the syscall. It cannot be
          # cancelled, so hand it a job to do when it eventually wakes: close
          # the socket it was building, or drop the error on the floor. Without
          # this, a late success leaks an fd nobody holds a reference to.
          spawn(name: "obsctl-obs-connect-discard") do
            late = results.receive
            late.close if late.is_a?(HTTP::WebSocket)
          rescue
          end
          raise connection_failed("timed out after #{timeout.total_milliseconds.to_i}ms")
        end
      end

      private def connection_failed(reason : String?) : Domain::ConnectionFailed
        Domain::ConnectionFailed.new(
          "failed to connect to OBS WebSocket at #{@config.host}:#{@config.port}: #{reason}"
        )
      end
    end
  end
end
