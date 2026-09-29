# frozen_string_literal: true

require "action_cable/subscription_adapter/base"
require "action_cable/subscription_adapter/channel_prefix"
require "action_cable/subscription_adapter/subscriber_map"
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
        @broadcaster = nil
      end

      def broadcast(channel, payload)
        broadcaster.broadcast(channel, payload)
      end

      def subscribe(channel, subscriber, success_callback = nil)
        listener.add_subscriber(channel, subscriber, success_callback)
      end

      def unsubscribe(channel, subscriber)
        listener.remove_subscriber(channel, subscriber)
      end

      def shutdown
        @broadcaster&.shutdown
        @listener&.shutdown
      end

      private
        def listener
          @listener || @mutex.synchronize do
            @listener ||= Listener.new(self, pubsub_executor)
          end
        end

        def broadcaster
          @broadcaster || @mutex.synchronize do
            @broadcaster ||= ::SolidCable::BatchedBroadcaster.new
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
            channels[::SolidCable::Message.channel_hash_for(channel)] = last_message_id
            on_success.call if on_success
          end

          def remove_channel(channel)
            channels.delete(::SolidCable::Message.channel_hash_for(channel))
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

            # Ids are assigned when an INSERT runs but become visible when it
            # commits, so a row can appear after a higher id was already read.
            # last_id therefore only moves past rows that have been read for
            # longer than late_commit_window; newer rows are excluded by id
            # instead, so a row that commits late is still read.
            def broadcast_messages
              messages = ::SolidCable::Message.broadcastable(channels.keys, last_id)
              messages = messages.where.not(id: recent_ids.keys) if recent_ids.any?

              read_at = monotonic_time
              messages.each do |message|
                recent_ids[message.id] = read_at
                broadcast(message) if subscribed_before?(message)
              end

              advance_last_id(read_at)
              self.reconnect_attempt = 0
            end

            # A channel only receives rows above the last id when it subscribed.
            def subscribed_before?(message)
              subscribed_at_id = channels[message.channel_hash]
              subscribed_at_id && subscribed_at_id < message.id
            end

            def advance_last_id(now)
              window = ::SolidCable.late_commit_window
              settled_id = recent_ids.filter_map { |id, read_at| id if now - read_at >= window }.max
              return unless settled_id

              self.last_id = settled_id
              recent_ids.delete_if { |id, _| id <= settled_id }
            end

            def recent_ids
              @recent_ids ||= {}
            end

            def monotonic_time
              Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end

            def broadcast(message)
              super(message.channel, message.payload)
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
