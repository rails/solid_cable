# frozen_string_literal: true

require "action_cable/subscription_adapter/base"
require "action_cable/subscription_adapter/channel_prefix"
require "action_cable/subscription_adapter/subscriber_map"
require "active_support/notifications"
require "concurrent/atomic/semaphore"

module ActionCable
  module SubscriptionAdapter
    class SolidCable < ::ActionCable::SubscriptionAdapter::Base
      prepend ::ActionCable::SubscriptionAdapter::ChannelPrefix

      def initialize(*)
        super
        @mutex =
          if defined?(@server)
            @server.mutex
          else
            Mutex.new
          end

        @listener = nil
      end

      def broadcast(channel, payload)
        ActiveSupport::Notifications.instrument("broadcast.solid_cable") do
          ::SolidCable::Message.broadcast(channel, payload)
        end

        ::SolidCable::TrimJob.perform_now if ::SolidCable.autotrim?
      end

      def subscribe(channel, callback, success_callback = nil)
        listener.add_subscriber(channel, callback, success_callback)
      end

      def unsubscribe(channel, callback)
        listener.remove_subscriber(channel, callback)
      end

      delegate :shutdown, to: :listener

      private
        def listener
          @listener || @mutex.synchronize do
            @listener ||= Listener.new(self, pubsub_executor)
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
            @last_poll_started_at = nil

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
            queued_at = monotonic_time

            executor.post do
              ActiveSupport::Notifications.instrument(
                "callback.solid_cable",
                queue_ms: milliseconds_since(queued_at)
              ) { super }
            end
          end

          private
            attr_reader :executor, :thread
            attr_accessor :last_id, :reconnect_attempt

            def last_message_id
              ActiveSupport::Notifications.instrument("subscription_cursor.solid_cable") do
                ::SolidCable::Message.maximum(:id) || 0
              end
            end

            def channels
              @channels ||= Concurrent::Map.new
            end

            def broadcast_messages
              current_channels = channels.dup
              poll_started_at = monotonic_time
              payload = {
                interval_ms: @last_poll_started_at && milliseconds_since(@last_poll_started_at)
              }
              @last_poll_started_at = poll_started_at

              messages = ActiveSupport::Notifications.instrument("poll.solid_cable", payload) do
                columns = [ :id, :channel, :payload ]
                columns << :created_at if ActiveSupport::Notifications.notifier.listening?("poll.solid_cable")

                ::SolidCable::Message.
                  broadcastable(current_channels.keys, last_id).
                  pluck(*columns).tap do |records|
                    payload[:rows] = records.size
                    payload[:lags_ms] =
                      if columns.include?(:created_at)
                        now = Time.current
                        records.filter_map do |_, _, _, created_at|
                          (now - created_at) * 1_000 if created_at
                        end
                      end
                    payload[:pool] = ::SolidCable::Message.connection_pool.stat
                  end
              end

              messages.each do |id, channel, message_payload, _created_at|
                should_broadcast_message = false
                channels.compute_if_present(channel) do |channel_last_id|
                  break if channel_last_id >= id

                  should_broadcast_message = true
                  id
                end

                broadcast(channel, message_payload) if should_broadcast_message
                self.last_id = id
              end

              self.reconnect_attempt = 0
            end

            def monotonic_time
              Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end

            def milliseconds_since(started_at)
              (monotonic_time - started_at) * 1_000
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
