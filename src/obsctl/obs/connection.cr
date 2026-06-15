require "http/web_socket"
require "uri"
require "../config/config"
require "../domain/errors"

module Obsctl
  module OBS
    class Connection
      getter websocket

      def initialize(@config : Config::ConnectionConfig)
        @websocket = uninitialized HTTP::WebSocket
      end

      def connect : HTTP::WebSocket
        uri = URI.parse("ws://#{@config.host}:#{@config.port}")
        @websocket = HTTP::WebSocket.new(uri)
      rescue ex
        raise Domain::ConnectionFailed.new("failed to connect to OBS WebSocket at #{@config.host}:#{@config.port}: #{ex.message}")
      end
    end
  end
end
