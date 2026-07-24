# frozen_string_literal: true

require "action_cable/subscription_adapter/base"
require "action_cable/subscription_adapter/channel_prefix"
require "action_cable/subscription_adapter/subscriber_map"
require "concurrent/atomic/semaphore"

module ActionCable
  module SubscriptionAdapter
    class SolidCable < ::ActionCable::SubscriptionAdapter::Base
      prepend ::ActionCable::SubscriptionAdapter::ChannelPrefix

      class Writer
        Stopped = Class.new(StandardError)

        Request = Struct.new(
          :channel,
          :payload,
          :enqueued_at,
          :completed,
          :error,
          keyword_init: true
        )

        def initialize(batch_size:, batch_delay:)
          @batch_size = batch_size
          @batch_delay = batch_delay

          @mutex = Mutex.new
          @ready = ConditionVariable.new
          @queue = []
          @stopping = false

          @thread = Thread.new do
            Thread.current.name = "solid_cable_writer"
            Thread.current.report_on_exception = true
            run
          end
        end

        def write(channel, payload)
          request = Request.new(
            channel: channel,
            payload: payload,
            enqueued_at: monotonic_time,
            completed: Concurrent::Event.new
          )

          @mutex.synchronize do
            raise Stopped, "Solid Cable writer has stopped" if @stopping

            @queue << request
            @ready.signal
          end

          request.completed.wait
          raise request.error if request.error
        end

        def shutdown
          @mutex.synchronize do
            @stopping = true
            @ready.broadcast
          end

          @thread.join
        end

        private
          def run
            while batch = take_batch
              flush(batch)
            end
          ensure
            fail_pending_requests
          end

          def take_batch
            @mutex.synchronize do
              @ready.wait(@mutex) while @queue.empty? && !@stopping

              return if @queue.empty?

              wait_for_batch unless @stopping
              @queue.shift(@batch_size)
            end
          end

          def wait_for_batch
            deadline = @queue.first.enqueued_at + @batch_delay

            while @queue.size < @batch_size
              remaining = deadline - monotonic_time
              break unless remaining.positive?

              @ready.wait(@mutex, remaining)
            end
          end

          def flush(batch)
            error = nil

            begin
              Rails.application.executor.wrap do
                ::SolidCable::Message.broadcast_batch(
                  batch.map { |request| [request.channel, request.payload] }
                )
              end
            rescue StandardError => caught
              error = caught
            ensure
              batch.each do |request|
                request.error = error
                request.completed.set
              end
            end
          end

          def fail_pending_requests
            requests = @mutex.synchronize { @queue.shift(@queue.length) }

            requests.each do |request|
              request.error = Stopped.new("Solid Cable writer stopped before committing")
              request.completed.set
            end
          end

          def monotonic_time
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
      end

      def initialize(*)
        super
        @mutex =
          if defined?(@server)
            @server.mutex
          else
            Mutex.new
          end

        @listener = nil
        @writer = nil
      end

      def broadcast(channel, payload)
        writer.write(channel, payload)

        ::SolidCable::TrimJob.perform_now if ::SolidCable.autotrim?
      end

      def subscribe(channel, callback, success_callback = nil)
        listener.add_subscriber(channel, callback, success_callback)
      end

      def unsubscribe(channel, callback)
        listener.remove_subscriber(channel, callback)
      end

      def shutdown
        @writer&.shutdown
        @listener&.shutdown
      end

      private
        def listener
          @listener || @mutex.synchronize do
            @listener ||= Listener.new(self, pubsub_executor)
          end
        end

        # batch size:  1, 4, 8, 16, 32
        # delay:       0ms, 0.5ms, 1ms, 2ms
        def writer
          @writer || @mutex.synchronize do
            @writer ||= Writer.new(
              batch_size: ::SolidCable.writer_batch_size,
              batch_delay: ::SolidCable.writer_batch_delay
            )
          end
        end

        def pubsub_executor
          @pubsub_executor ||=
            if respond_to?(:executor, true)
              executor
            else
              @server.event_loop
            end
        end

        class Listener < ::ActionCable::SubscriptionAdapter::SubscriberMap
          CONNECTION_ERRORS = [
            ActiveRecord::ConnectionFailed,
            ActiveRecord::ConnectionTimeoutError,
            ActiveRecord::ConnectionNotEstablished
          ]
          Stop = Class.new(Exception)

          delegate :logger, to: :@adapter

          def initialize(adapter, executor)
            super()
            @adapter = adapter
            @executor = executor

            # Critical section begins with 0 permits. It can be understood as
            # being "normally held" by the listener thread. It is released
            # for specific sections of code, rather than acquired.
            @critical = Concurrent::Semaphore.new(0)

            @reconnect_attempt = 0
            @last_id = last_message_id

            @thread = Thread.new do
              Thread.current.name = "solid_cable_listener"
              Thread.current.report_on_exception = true

              begin
                listen
              rescue *CONNECTION_ERRORS
                retry if retry_connecting?
              end
            end
          end

          def listen
            loop do
              begin
                instance = interruptible { Rails.application.executor.run! }
                with_polling_volume { broadcast_messages }
              ensure
                instance.complete! if instance
              end

              interruptible { sleep ::SolidCable.polling_interval }
            end
          rescue Stop
          ensure
            @critical.release
          end

          def interruptible
            @critical.release
            yield
          ensure
            @critical.acquire
          end

          def shutdown
            @critical.acquire
            # We have the critical permit, and so the listen thread must be
            # safe to interrupt.
            thread.raise(Stop)
            @critical.release
            thread.join
          end

          def add_channel(channel, on_success)
            channels[channel] = last_message_id
            on_success.call if on_success
          end

          def remove_channel(channel)
            channels.delete(channel)
          end

          def invoke_callback(*)
            executor.post { super }
          end

          private
            attr_reader :executor, :thread
            attr_accessor :last_id, :reconnect_attempt

            def last_message_id
              ::SolidCable::Message.maximum(:id) || 0
            end

            def channels
              @channels ||= Concurrent::Map.new
            end

            def broadcast_messages
              ::SolidCable::Message.
                where(id: (last_id.to_i + 1)..).
                order(:id).
                pluck(:id, :channel, :payload).each do |id, channel, payload|
                  should_broadcast_message = false
                  channels.compute_if_present(channel) do |channel_last_id|
                    break if channel_last_id >= id

                    should_broadcast_message = true
                    id
                  end

                  broadcast(channel, payload) if should_broadcast_message
                  self.last_id = id
                end

              self.reconnect_attempt = 0
            end

            def with_polling_volume
              if ::SolidCable.silence_polling? && ActiveRecord::Base.logger
                ActiveRecord::Base.logger.silence { yield }
              else
                yield
              end
            end

            def reconnect_attempts
              @reconnect_attempts ||= ::SolidCable.reconnect_attempts
            end

            def retry_connecting?
              self.reconnect_attempt += 1

              return false if reconnect_attempt > reconnect_attempts.size

              sleep_t = reconnect_attempts[reconnect_attempt - 1]

              sleep(sleep_t) if sleep_t > 0

              true
            end
        end
    end
  end
end
