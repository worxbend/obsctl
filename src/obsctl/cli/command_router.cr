require "../config/config"
require "../domain/command"
require "../domain/command_result"
require "../ipc/socket_path"
require "../ipc/unix_client"
require "./client_commands"

module Obsctl
  module CLI
    # Legacy command router kept as a thin IPC proxy for daemon-first command paths.
    class CommandRouter
      def initialize(@config : Config::Config, @config_path : String)
      end

      def execute(command : Domain::Command) : Domain::CommandResult
        case command
        when Domain::HelpCommand
          Domain::CommandResult.ok(help_text)
        when Domain::ConnectCommand
          proxy.execute(Domain::ServerStatusCommand.new)
          Domain::CommandResult.ok("connected")
        when Domain::DisconnectCommand
          Domain::CommandResult.ok("disconnected")
        when Domain::QuitCommand
          Domain::CommandResult.ok("quit")
        else
          proxy.execute(command)
        end
      end

      private def proxy : ClientCommands
        socket_path = IPC::SocketPath.resolve(@config.server.socket_path)
        ClientCommands.new(IPC::UnixClient.new(socket_path))
      end

      private def help_text : String
        "/help /set-scene <target> /scene <target> /mute <target> /unmute <target> /toggle-mute <target> /vol <target> <0-100> /status /server-status /obs-status /reconnect /validate-config /dump-config /reload-config /connect /disconnect /quit"
      end
    end
  end
end
