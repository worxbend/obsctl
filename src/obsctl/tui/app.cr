require "../../crytui"
require "../ipc/socket_path"
require "./dispatcher"
require "./event_applier"
require "./widgets/dashboard"
require "./widgets/connection"
require "./widgets/settings"

module Obsctl
  module TUI
    record SubscriptionMessage,
      generation : Int32,
      event : IPC::Event? = nil,
      error : String? = nil

    alias AppMessage = CryTUI::InputEvent | SubscriptionMessage

    class App
      DEFAULT_REFRESH = 100.milliseconds
      ESCAPE_DELAY    = 25.milliseconds

      getter model : Model

      def initialize(
        @socket_path : String = IPC::SocketPath.resolve,
        @input : IO::FileDescriptor = STDIN,
        @output : IO = STDOUT,
        @refresh : Time::Span = DEFAULT_REFRESH,
        @model = Model.new,
      )
        @messages = Channel(AppMessage).new(128)
        @subscription = nil.as(EventSession?)
        @subscription_generation = 0
        @running = false
      end

      def run : Int32
        backend = CryTUI::AnsiBackend.for_terminal(@output, @input)
        terminal = CryTUI::Terminal.new(backend)
        command_client = CommandClient.new(@socket_path)
        dispatcher = Dispatcher.new(@model, ->(payload : IPC::CommandPayload) { command_client.send(payload) })
        connect_subscription
        terminal.run(@input) do
          @running = true
          spawn_input_pump
          loop do
            render(terminal)
            should_quit = false
            select
            when message = @messages.receive
              should_quit = process(message, dispatcher)
            when timeout(@refresh)
              @model.anim.tick
              terminal.refresh_size
            end
            break if should_quit
          end
        ensure
          @running = false
          @subscription.try(&.close)
        end
        0
      rescue ex : IO::Error
        @output.puts "obsctl TUI failed: #{ex.message}"
        1
      end

      def process(message : AppMessage, dispatcher : Dispatcher) : Bool
        case message
        when CryTUI::KeyEvent
          if action = Input.handle_key(@model, message)
            apply_outcome(dispatcher.handle(action))
          else
            false
          end
        when CryTUI::PasteEvent
          if @model.command_palette.active
            @model.command_palette.input += message.text.gsub(/[\x00-\x08\x0B-\x1F\x7F]/, "")
            @model.command_palette.completions = Completion.compute(@model.command_palette.input, @model)
            @model.command_palette.completion_index = nil
          end
          false
        when SubscriptionMessage
          return false unless message.generation == @subscription_generation
          if event = message.event
            EventApplier.apply(@model, event)
          else
            @model.connected_to_daemon = false
            @model.last_result = message.error || "server connection closed"
          end
          false
        else
          false
        end
      end

      def render(terminal : CryTUI::Terminal)
        terminal.draw do |frame|
          if @model.view.settings?
            Widgets::Settings.render(frame.area, frame.buffer, @model)
          elsif @model.connected_to_daemon
            Widgets::Dashboard.render(frame.area, frame.buffer, @model)
          else
            frame.buffer.set_style(frame.area, CryTUI::Style.new(background: @model.theme.background, foreground: @model.theme.foreground))
            Widgets::Connection.render_unavailable(frame.area, frame.buffer, @model)
          end
        end
      end

      private def apply_outcome(outcome : ActionOutcome) : Bool
        @model.set_last_result(outcome.message.not_nil!) if outcome.message
        connect_subscription if outcome.retry_subscription
        outcome.quit
      end

      private def connect_subscription
        @subscription_generation += 1
        generation = @subscription_generation
        @subscription.try(&.close)
        session = EventSession.connect(@socket_path)
        @subscription = session
        @model.connected_to_daemon = true
        spawn(name: "obsctl-tui-ipc") do
          while event = session.next_event
            @messages.send(SubscriptionMessage.new(generation, event: event))
          end
          @messages.send(SubscriptionMessage.new(generation, error: "server connection closed"))
        rescue ex
          @messages.send(SubscriptionMessage.new(generation, error: ex.message || "server connection failed"))
        end
      rescue ex : Domain::ObsctlError
        @subscription = nil
        @model.connected_to_daemon = false
        @model.last_result = ex.message
      end

      private def spawn_input_pump
        parser = CryTUI::InputParser.new
        spawn(name: "obsctl-tui-input") do
          while @running && (character = @input.read_char)
            events = parser.feed(character.to_s)
            events.each { |event| @messages.send(event) if @running }
            if character == '\e'
              spawn do
                sleep ESCAPE_DELAY
                parser.flush_escape.each { |event| @messages.send(event) if @running }
              end
            end
          end
        rescue IO::Error
        end
      end
    end
  end
end
