require "json"
require "../config/config"
require "../domain/errors"
require "../obs/client"
require "../obs/protocol/event_subscription"
require "../obs/protocol/obs_event"
require "../runtime/logger"
require "../runtime/reconnect_policy"
require "./log_payload"
require "./reconnect_signal"
require "./state_store"

module Obsctl
  module Server
    # Owns the single OBS WebSocket client and reconnect loop for the daemon.
    class ObsSupervisor
      DISCONNECT_FALLBACK_TIMEOUT = 100.milliseconds
      STATS_POLL_INTERVAL         = 2.seconds

      enum LifecycleState
        Starting
        Running
        Stopped
      end

      private record ReconnectPublication,
        detached_client : OBS::Client?,
        state_payload : JSON::Any,
        log_payload : JSON::Any

      # Creates a supervisor that updates server state and optional event/log broadcasts.
      def initialize(
        @config : Config::Config,
        @state : StateStore,
        @event_broadcast : Proc(JSON::Any, Nil)? = nil,
        @log_broadcast : Proc(JSON::Any, Nil)? = nil,
        @logger : Runtime::Logger? = nil,
        @diagnostic_log_broadcast : Proc(JSON::Any, Bool)? = nil,
        @stats_poll_interval : Time::Span = STATS_POLL_INTERVAL,
      )
        @client = nil.as(OBS::Client?)
        @client_lock = Mutex.new
        @lifecycle_lock = Mutex.new
        @lifecycle_state = LifecycleState::Stopped
        @lifecycle_generation = 0_u64
        @reconnect_signal = nil.as(ReconnectSignal?)
        @stopped_reconnect_attempted = false
        @test_reconnect_before_publication = nil.as(Proc(Nil)?)
      end

      # Test-only observability for reconnect attempts rejected by stopped lifecycle state.
      def stopped_reconnect_attempted? : Bool
        @lifecycle_lock.synchronize { @stopped_reconnect_attempted }
      end

      # Test-only synchronization hook invoked after `reconnect` captures a
      # live generation and before it re-checks that generation for public
      # reconnect publication. The hook runs without supervisor locks held and
      # may block to coordinate deterministic race specs.
      property test_reconnect_before_publication : Proc(Nil)?

      # Returns true while the supervisor loop is starting or can still act.
      def alive? : Bool
        @lifecycle_lock.synchronize { @lifecycle_state != LifecycleState::Stopped }
      end

      # Starts the reconnecting supervisor loop in a background fiber.
      def start : Nil
        generation, reconnect_signal = @lifecycle_lock.synchronize do
          return unless @lifecycle_state == LifecycleState::Stopped

          @lifecycle_generation += 1
          @lifecycle_state = LifecycleState::Starting
          signal = ReconnectSignal.new
          @reconnect_signal = signal
          @stopped_reconnect_attempted = false
          {@lifecycle_generation, signal}
        end
        spawn(name: "obsctl-obs-supervisor") { run(generation, reconnect_signal) }
      end

      # Stops reconnect attempts and closes the active OBS client.
      def stop : Nil
        reconnect_signal = @lifecycle_lock.synchronize do
          @lifecycle_generation += 1
          @lifecycle_state = LifecycleState::Stopped
          signal = @reconnect_signal
          @reconnect_signal = nil
          signal
        end
        reconnect_signal.try(&.cancel)
        current_client = @client_lock.synchronize do
          existing = @client
          @client = nil
          existing
        end
        current_client.try(&.close)
      end

      # Yields the active OBS client or raises when OBS is unavailable.
      def with_client(&block : OBS::Client -> T) : T forall T
        client = @client_lock.synchronize { @client }
        raise Domain::ObsUnavailable.new unless client && client.connected?
        block.call(client)
      end

      # Drops the active client so the supervisor reconnect loop starts over.
      def reconnect : Bool
        generation, reconnect_signal = @lifecycle_lock.synchronize do
          if @lifecycle_state == LifecycleState::Stopped
            @stopped_reconnect_attempted = true
            return false
          end

          signal = @reconnect_signal
          return false unless signal

          {@lifecycle_generation, signal}
        end

        @test_reconnect_before_publication.try(&.call)

        publication = @lifecycle_lock.synchronize do
          if @lifecycle_state == LifecycleState::Stopped ||
             @lifecycle_generation != generation ||
             @reconnect_signal != reconnect_signal
            @stopped_reconnect_attempted = true if @lifecycle_state == LifecycleState::Stopped
            nil
          else
            accepted_at = Time.utc
            reconnect_signal.request
            detached_client = @client_lock.synchronize do
              existing = @client
              @client = nil
              existing
            end
            ReconnectPublication.new(
              detached_client,
              @state.mark_reconnect_requested_and_build_payload(accepted_at),
              log_payload("info", "obs_reconnect_requested", "OBS reconnect requested", accepted_at)
            )
          end
        end

        return false unless publication

        publish_reconnect(publication)
        true
      end

      private def run(generation : UInt64, reconnect_signal : ReconnectSignal) : Nil
        return unless mark_running(generation)

        policy = Runtime::ReconnectPolicy.new(@config.reconnect)
        attempt = 0

        until stopped?(generation)
          client = OBS::Client.new(@config, event_subscriptions: OBS::Protocol::EventSubscription::SERVER_DEFAULT)
          handled_request_epoch = reconnect_signal.latest_request_epoch
          begin
            @state.mark_reconnect_attempt
            client.connect
            break unless claim_client(generation, client)

            @state.mark_connected(client.snapshot)
            publish_log("info", "obs_connected", "Connected to OBS WebSocket")
            attempt = 0

            disconnect_error = wait_for_disconnect(generation, client)
            next if client_detached?(client)
            raise(disconnect_error || Domain::ConnectionFailed.new("OBS WebSocket disconnected")) unless stopped?(generation)
          rescue ex
            break if stopped?(generation)

            message = failure_message(ex)
            @state.mark_disconnected(message, reconnecting: @config.reconnect.enabled)
            delay = policy.delay_for(attempt)
            publish_failure(ex, message, delay, attempt)

            next_attempt = settle_after_failure(generation, client, delay, reconnect_signal, handled_request_epoch, attempt)
            break unless next_attempt
            attempt = next_attempt
          end
        end
      ensure
        mark_stopped(generation)
      end

      # What the user is told after a failure took the OBS session down.
      #
      # A `Domain::ObsctlError` is a failure the daemon anticipated — OBS
      # refused a request, the socket went away, the password was wrong — so
      # its own message is the best account available. Anything else is a fault
      # in the supervisor itself and says so.
      private def failure_message(error : Exception) : String
        fallback = error.is_a?(Domain::ObsctlError) ? "OBS unavailable" : "OBS supervisor failed"
        public_message(error.message, fallback)
      end

      # Writes the log line(s) for a failure that ended the OBS session.
      #
      # An anticipated failure is one warning that already names the retry.
      # An unexpected one is logged at error level under its own code first,
      # and the retry note follows as a separate line so an operator reading
      # the log does not mistake a supervisor bug for the ordinary reconnect
      # churn.
      private def publish_failure(error : Exception, message : String, delay : Time::Span, attempt : Int32) : Nil
        if error.is_a?(Domain::ObsctlError)
          publish_log("warn", disconnect_log_code(error), retry_warning(message, delay, attempt))
          return
        end

        publish_log("error", "obs_supervisor_error", message)
        return unless @config.reconnect.enabled

        publish_log("warn", "obs_reconnect_scheduled", retry_warning(message, delay, attempt))
      end

      # Releases a failed client and waits out the backoff before the next try.
      #
      # Returns the attempt counter to continue with, or nil when the retry loop
      # should stop. Both rescue arms in `run` end this way; they differ only in
      # how they describe the failure.
      private def settle_after_failure(
        generation : UInt64,
        client : OBS::Client,
        delay : Time::Span,
        reconnect_signal : ReconnectSignal,
        handled_request_epoch : UInt64,
        attempt : Int32,
      ) : Int32?
        # Unconditional: a client whose socket opened but whose Identify failed
        # (a wrong password, say) still holds an fd and a live reader fiber.
        # `Client#close` is a no-op when the socket never opened.
        client.close
        @client_lock.synchronize { @client = nil if @client == client }
        return if stopped?(generation) || !@config.reconnect.enabled

        case reconnect_signal.wait(delay, handled_request_epoch)
        when ReconnectSignal::WaitResult::Requested
          # Explicit reconnect request consumed — retry immediately without
          # incrementing backoff.
          attempt
        when ReconnectSignal::WaitResult::Cancelled
          nil # Stop-initiated cancel; exit the retry loop immediately.
        else
          # TimedOut or Interrupted: follow the normal backoff path.
          attempt + 1
        end
      end

      private def wait_for_disconnect(generation : UInt64, client : OBS::Client) : Domain::ConnectionFailed?
        last_stream_sample = nil.as(Tuple(Int64, Time::Instant)?)
        next_stats_poll = Time.instant + @stats_poll_interval
        loop do
          drain_events(client)
          return client.terminal_error if client.terminal_error
          return client.terminal_error if stopped?(generation) || !client.connected?

          if Time.instant >= next_stats_poll
            last_stream_sample = poll_stats(client, last_stream_sample)
            next_stats_poll = Time.instant + @stats_poll_interval
          end

          if error = client.wait_for_close(DISCONNECT_FALLBACK_TIMEOUT)
            return error
          end
        end
      end

      private def poll_stats(
        client : OBS::Client,
        previous : Tuple(Int64, Time::Instant)?,
      ) : Tuple(Int64, Time::Instant)?
        sample = client.telemetry_sample
        now = Time.instant
        current = sample.stream_active ? sample.stream_bytes.try { |bytes| {bytes, now} } : nil
        bitrate = if current && previous
                    bytes, measured_at = current
                    previous_bytes, previous_at = previous
                    elapsed = (measured_at - previous_at).total_seconds
                    if bytes >= previous_bytes && elapsed > 0
                      (bytes - previous_bytes).to_f64 * 8.0 / 1000.0 / elapsed
                    end
                  end
        # The poll also reconciles output state. Events are the fast path, but
        # this is what guarantees convergence if one is ever missed: `drain_events`
        # runs before this in the same fiber, so the answer can never be older
        # than the last event applied.
        @state.update_stats(
          sample.stats, bitrate, sample.stream_duration_ms, sample.record_duration_ms,
          streaming: sample.stream_active, recording: sample.record_active
        )
        current
      rescue ex : Domain::ObsctlError
        publish_log("warn", "obs_stats_poll_failed", public_message(ex.message, "failed to poll OBS telemetry"))
        previous
      end

      private def stopped?(generation : UInt64) : Bool
        @lifecycle_lock.synchronize do
          @lifecycle_state == LifecycleState::Stopped || @lifecycle_generation != generation
        end
      end

      private def claim_client(generation : UInt64, client : OBS::Client) : Bool
        claimed = false
        @lifecycle_lock.synchronize do
          return false if @lifecycle_state == LifecycleState::Stopped || @lifecycle_generation != generation

          @client_lock.synchronize { @client = client }
          claimed = true
        end
        claimed
      ensure
        client.close unless claimed
      end

      private def mark_running(generation : UInt64) : Bool
        @lifecycle_lock.synchronize do
          return false unless @lifecycle_generation == generation
          return false if @lifecycle_state == LifecycleState::Stopped

          @lifecycle_state = LifecycleState::Running
          true
        end
      end

      private def mark_stopped(generation : UInt64) : Nil
        @lifecycle_lock.synchronize do
          next unless @lifecycle_generation == generation

          @lifecycle_state = LifecycleState::Stopped
          @reconnect_signal = nil
        end
      end

      private def drain_events(client : OBS::Client) : Nil
        loop do
          select
          when event = client.events.receive
            publish_event(event)
            apply_event(event, client)
          when timeout(0.milliseconds)
            break
          end
        end
      rescue ex : Domain::ObsctlError
        report_event_refresh_failure(ex)
      end

      # Folds one OBS event into the authoritative state cache.
      #
      # The event arrives already translated (see `Protocol::ObsEvent`), so
      # everything below is about what the daemon does, not about what OBS
      # sent. Some events carry the new value and are applied directly; others
      # only say "this list is no longer what you think it is", and the daemon
      # answers those by re-reading from OBS.
      private def apply_event(event : OBS::Protocol::Event, client : OBS::Client) : Nil
        case translated = OBS::Protocol::ObsEvent.from(event)
        when OBS::Protocol::ObsEvent::ProgramSceneChanged
          @state.update_current_scene(translated.scene_name)
        when OBS::Protocol::ObsEvent::InputMuteChanged
          @state.update_input_mute(translated.input_name, translated.muted)
        when OBS::Protocol::ObsEvent::InputVolumeChanged
          @state.update_input_volume(translated.input_name, translated.volume_mul, translated.volume_db)
        when OBS::Protocol::ObsEvent::SceneListChanged
          refresh = client.scene_snapshot
          @state.update_scenes(refresh[:current_scene], refresh[:scenes])
        when OBS::Protocol::ObsEvent::InputListChanged
          @state.update_audio_inputs(client.audio_snapshot)
        when OBS::Protocol::ObsEvent::StreamStateChanged
          @state.update_output(streaming: translated.active)
        when OBS::Protocol::ObsEvent::RecordStateChanged
          @state.update_output(recording: translated.active)
        when OBS::Protocol::ObsEvent::StudioContextChanged
          @state.update(client.snapshot)
        end
      rescue ex : Domain::ObsctlError
        report_event_refresh_failure(ex)
      end

      private def client_detached?(client : OBS::Client) : Bool
        @client_lock.synchronize { @client != client }
      end

      private def publish_event(event : OBS::Protocol::Event) : Nil
        @event_broadcast.try(&.call(JSON.parse({
          event_type: event.event_type,
          event_data: event.event_data,
        }.to_json)))
      end

      private def publish_log(level : String, code : String, message : String) : Nil
        @log_broadcast.try(&.call(log_payload(level, code, message)))
      end

      private def log_payload(level : String, code : String, message : String, at : Time = Time.utc) : JSON::Any
        LogPayload.build(level, code, Runtime::Logger.redact_secrets(message), at)
      end

      private def publish_reconnect(publication : ReconnectPublication) : Nil
        detached_client = publication.detached_client
        detached_client_closed = false
        begin
          detached_client.try do |client|
            client.close
            detached_client_closed = true
          end
          publish_reconnect_state(publication.state_payload)
          publish_reconnect_log(publication.log_payload)
        ensure
          detached_client.try(&.close) unless detached_client_closed
        end
      end

      private def publish_reconnect_state(payload : JSON::Any) : Nil
        @state.publish_snapshot_payload(payload)
      rescue ex
        publish_reconnect_diagnostic(
          "obs_reconnect_state_publication_failed",
          "OBS reconnect state publication failed",
          ex
        )
      end

      private def publish_reconnect_log(payload : JSON::Any) : Nil
        @log_broadcast.try(&.call(payload))
      rescue ex
        publish_reconnect_diagnostic(
          "obs_reconnect_log_publication_failed",
          "OBS reconnect log publication failed",
          ex
        )
      end

      private def publish_reconnect_diagnostic(code : String, message : String, cause : Exception) : Nil
        diagnostic = "#{message}: #{exception_summary(cause)}"
        write_reconnect_diagnostic(code, diagnostic)

        broadcast = @diagnostic_log_broadcast
        return unless broadcast

        begin
          broadcast.call(log_payload("warn", code, diagnostic))
        rescue
        end
      end

      private def write_reconnect_diagnostic(code : String, message : String) : Nil
        @logger.try(&.warn("#{code} #{Runtime::Logger.redact_secrets(message)}"))
      rescue
      end

      private def exception_summary(ex : Exception) : String
        exception_name = ex.class.name || "Exception"
        message = ex.message
        return exception_name if message.nil? || message.empty?

        "#{exception_name}: #{Runtime::Logger.redact_secrets(message)}"
      end

      private def public_message(message : String?, fallback : String) : String
        Runtime::Logger.redact_secrets(message || fallback)
      end

      # The log code for a failure that took the OBS session down.
      #
      # Derived from the exception's type and its own account of what happened,
      # never from the wording of its message — see `Domain::DisconnectKind`.
      private def disconnect_log_code(error : Exception) : String
        case error
        when Domain::ObsRequestFailed
          # The socket is fine; OBS refused one request. Logging this as a
          # disconnect sends operators looking for a network fault that is not
          # there.
          "obs_request_failed"
        when Domain::ConnectionFailed
          error.kind.log_code
        else
          Domain::DisconnectKind::Disconnected.log_code
        end
      end

      private def retry_warning(message : String, delay : Time::Span, attempt : Int32) : String
        return message unless @config.reconnect.enabled

        milliseconds = delay.total_milliseconds.to_i64
        "#{message}; reconnect attempt #{attempt + 1} scheduled in #{milliseconds}ms"
      end

      # Both draining and applying an event can fail the same way: by asking
      # OBS for the list an event only announced had changed. Either way the
      # cached state is now behind what OBS holds, which is what subscribers
      # are told.
      private def report_event_refresh_failure(error : Domain::ObsctlError) : Nil
        message = public_message(error.message, "failed to refresh OBS state after event")
        @state.mark_disconnected(message)
        publish_log("warn", "obs_event_refresh_failed", message)
      end
    end
  end
end
