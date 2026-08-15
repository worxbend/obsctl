require "../../crytui"
require "../ipc/socket_path"
require "../config/config"
require "./dispatcher"
require "./event_applier"
require "./widgets/dashboard"
require "./widgets/connection"
require "./widgets/settings"
require "./widgets/splash"
require "./widgets/scene_picker"
require "./widgets/which_key"
require "./theme_persistence"

module Obsctl
  module TUI
    record SubscriptionMessage,
      generation : Int32,
      event : IPC::Event? = nil,
      error : String? = nil

    record InputClosed
    record ResizeDetected

    alias AppMessage = CryTUI::InputEvent | SubscriptionMessage | InputClosed | ResizeDetected

    class App
      DEFAULT_REFRESH = 100.milliseconds
      ESCAPE_DELAY    = 25.milliseconds
      SPLASH_DURATION = 2.seconds
      SPLASH_FRAME    = 50.milliseconds
      RESIZE_POLL     = 50.milliseconds

      getter model : Model
      getter refresh : Time::Span

      # Whether a frame is owed before the run loop next waits for input.
      getter? needs_render : Bool

      def self.from_config(config : Config::Config, socket_path : String = IPC::SocketPath.resolve, input : IO::FileDescriptor = STDIN, output : IO = STDOUT, config_path : String? = nil) : self
        custom = config.ui.custom_theme.try do |theme|
          CustomThemeSpec.new(
            background: theme.bg, accent: theme.accent, accent_alt: theme.accent_alt,
            foreground: theme.fg, muted: theme.muted, border: theme.border,
            border_focus: theme.border_focus, success: theme.success, warning: theme.warning,
            danger: theme.danger, info: theme.info, highlight_background: theme.highlight_bg,
            highlight_foreground: theme.highlight_fg
          )
        end
        prefix = config.ui.command_palette_prefix.empty? ? "/" : config.ui.command_palette_prefix
        model = Model.new(
          theme: Theme.resolve(config.ui.theme, custom),
          show_icons: config.ui.show_icons,
          advanced_ui: config.ui.advanced_ui,
          command_palette_prefix: prefix,
          locale: Localization.resolve(config.ui.locale)
        )
        new(
          socket_path: socket_path,
          input: input,
          output: output,
          refresh: {config.ui.refresh_interval_ms, 50}.max.milliseconds,
          model: model,
          config_path: config_path
        )
      end

      def initialize(
        @socket_path : String = IPC::SocketPath.resolve,
        @input : IO::FileDescriptor = STDIN,
        @output : IO = STDOUT,
        @refresh : Time::Span = DEFAULT_REFRESH,
        @model = Model.new,
        @config_path : String? = nil,
      )
        @messages = Channel(AppMessage).new(128)
        @area = CryTUI::Rect.new(0, 0, 0, 0)
        @subscription = nil.as(EventSession?)
        @subscription_generation = 0
        @running = false
        @exit_code = 0
        # "Something changed since the last frame." The run loop paints its
        # first frame unconditionally and clears this, so it starts false.
        @needs_render = false
      end

      def run : Int32
        backend = CryTUI::AnsiBackend.for_terminal(@output, @input)
        terminal = CryTUI::Terminal.new(backend)
        terminal.run(@input) do
          @running = true
          @exit_code = 0
          spawn_input_pump
          spawn_resize_pump
          run_splash(terminal)
          next unless @exit_code == 0
          command_client = CommandClient.new(@socket_path)
          dispatcher = Dispatcher.new(
            @model,
            ->(payload : IPC::CommandPayload) { command_client.send(payload) },
            ->(theme : Theme) { ThemePersistence.save(@config_path, theme) },
            viewport: -> { @area }
          )
          connect_subscription
          # The first frame is unconditional; from here on a frame is painted
          # only when something has changed since the last one.
          render(terminal)
          @needs_render = false
          loop do
            should_quit = select
            when message = @messages.receive
              process(message, dispatcher)
            when timeout(@refresh)
              # The refresh tick advances spinners and clock-like readouts, so
              # it always redraws. It is also the backstop that bounds how long
              # a skipped meter update can go unpainted: at most one interval.
              @model.anim.tick
              @needs_render = true
              false
            end
            break if should_quit
            if @needs_render
              render(terminal)
              @needs_render = false
            end
          end
        ensure
          @running = false
          @subscription.try(&.close)
        end
        @exit_code
      rescue ex : IO::Error
        @output.puts "obsctl TUI failed: #{ex.message}"
        1
      end

      # Handles one message and returns whether the dashboard should exit.
      #
      # Sets `@needs_render` for anything that changes what is on screen. The
      # one exception is a pushed event, which decides for itself: volume
      # meters arrive tens of times a second and are content to be picked up by
      # the next refresh tick rather than forcing a frame each.
      def process(message : AppMessage, dispatcher : Dispatcher) : Bool
        @needs_render = true unless message.is_a?(SubscriptionMessage)
        case message
        when CryTUI::KeyEvent
          if action = Input.handle_key(@model, message)
            apply_outcome(dispatcher.handle(action))
          else
            false
          end
        when CryTUI::MouseEvent
          if action = Input.handle_mouse(@model, message, @area)
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
            # Applied first and combined after: `||=` would short-circuit and
            # never apply the event at all whenever a redraw is already owed.
            # The result is OR-ed in so an event that needs no redraw cannot
            # cancel one owed from an earlier pass.
            @needs_render = true if EventApplier.apply(@model, event)
          else
            @model.connected_to_daemon = false
            @model.set_last_result(message.error || "server connection closed")
            @needs_render = true
          end
          false
        when InputClosed
          @exit_code = 1
          true
        when ResizeDetected
          false
        else
          false
        end
      end

      def render(terminal : CryTUI::Terminal)
        terminal.draw do |frame|
          # Remembered so a mouse report can be resolved against the geometry
          # that was actually on screen when the user clicked.
          @area = frame.area
          if @model.view.settings?
            Widgets::Settings.render(frame.area, frame.buffer, @model)
          elsif @model.connected_to_daemon
            Widgets::Dashboard.render(frame.area, frame.buffer, @model)
          else
            frame.buffer.set_style(frame.area, CryTUI::Style.new(background: @model.theme.background, foreground: @model.theme.foreground))
            Widgets::Connection.render_unavailable(frame.area, frame.buffer, @model)
          end
          # Both float over whichever view is underneath. The which-key menu is
          # last because it is the more transient of the two: it belongs on top
          # even of the picker in the frame where `<leader>s` is still pending.
          Widgets::ScenePicker.render(frame.area, frame.buffer, @model)
          Widgets::WhichKey.render(frame.area, frame.buffer, @model)
        end
      end

      private def apply_outcome(outcome : ActionOutcome) : Bool
        if message = outcome.message
          @model.set_last_result(message)
        end
        connect_subscription(retry: true) if outcome.retry_subscription
        outcome.quit
      end

      private def run_splash(terminal : CryTUI::Terminal) : Nil
        total = (SPLASH_DURATION.total_milliseconds / SPLASH_FRAME.total_milliseconds).to_u64
        frame = 0_u64
        loop do
          terminal.draw { |draw| Widgets::Splash.render(draw.area, draw.buffer, @model, frame, total) }
          break if frame >= total
          dismissed = false
          select
          when message = @messages.receive
            if message.is_a?(InputClosed)
              @exit_code = 1
              dismissed = true
            else
              dismissed = message.is_a?(CryTUI::InputEvent)
            end
          when timeout(SPLASH_FRAME)
            frame &+= 1
            @model.anim.tick
          end
          break if dismissed
        end
      end

      private def connect_subscription(retry = false)
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
        message = ex.message || "server connection failed"
        @model.set_last_result(retry ? "Retry failed: #{message}" : message)
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
          @messages.send(InputClosed.new) if @running
        rescue IO::Error
          @messages.send(InputClosed.new) if @running
        end
      end

      private def spawn_resize_pump
        spawn(name: "obsctl-tui-resize") do
          previous = CryTUI::TerminalSize.from(@input)
          while @running
            sleep RESIZE_POLL
            current = CryTUI::TerminalSize.from(@input)
            next unless current && current != previous

            previous = current
            select
            when @messages.send(ResizeDetected.new)
            else
            end
          end
        end
      end
    end
  end
end
