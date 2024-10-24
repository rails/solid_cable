# frozen_string_literal: true

require "action_cable/subscription_adapter/base"
require "action_cable/subscription_adapter/channel_prefix"
require "action_cable/subscription_adapter/subscriber_map"

module ActionCable
  module SubscriptionAdapter
    class SolidCable < ::ActionCable::SubscriptionAdapter::Base
      prepend ::ActionCable::SubscriptionAdapter::ChannelPrefix

      def initialize(*)
        super
        @listener = nil
      end

      def broadcast(channel, payload)
        ::SolidCable::Message.broadcast(channel, payload)

        ::SolidCable::TrimJob.perform_now if ::SolidCable.autotrim?
      end

      def broadcast_list(channel, payload)
        ::SolidCable::Message.broadcast_list(channel, payload)

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
          @listener || @server.mutex.synchronize do
            @listener ||= Listener.new(@server.event_loop)
          end
        end

        class Listener < ::ActionCable::SubscriptionAdapter::SubscriberMap
          def initialize(event_loop)
            super()

            @event_loop = event_loop

            @thread = Thread.new do
              Thread.current.abort_on_exception = true
              listen
            end
          end

          def listen
            while running?
              with_polling_volume { broadcast_messages }

              sleep ::SolidCable.polling_interval
            end
          end

          def shutdown
            self.running = false
            Thread.pass while thread.alive?
          end

          def add_channel(channel, on_success)
            channels.add(channel)
            event_loop.post(&on_success) if on_success
          end

          def remove_channel(channel)
            channels.delete(channel)
          end

          def invoke_callback(*)
            event_loop.post { super }
          end

          private
            attr_reader :event_loop, :thread
            attr_writer :running, :last_id
            attr_writer :running, :last_list_id

            def running?
              if defined?(@running)
                @running
              else
                self.running = true
              end
            end

            def last_id
              @last_id ||= ::SolidCable::Message.where(broadcast_to_list: false).maximum(:id) || 0
            end

            def last_list_id
              @last_list_id ||= ::SolidCable::Message.where(broadcast_to_list: true).maximum(:id) || 0
            end

            def channels
              @channels ||= Set.new
            end

            def broadcast_messages
              ::SolidCable::Message.broadcastable(channels, last_id).
                each do |message|
                  broadcast(message.channel, message.payload)
                  self.last_id = message.id
                end

              ::SolidCable::Message.broadcastable_to_list(channels, last_list_id).
                each do |message|
                  find_matching_channels(message.channel, channels).each do |channel|
                    broadcast(channel, message.payload)
                  end
                  self.last_list_id = message.id
                end
            end

            def with_polling_volume
              if ::SolidCable.silence_polling? && ActiveRecord::Base.logger
                ActiveRecord::Base.logger.silence { yield }
              else
                yield
              end
            end

          # Returns a list of channels that match the broadcast_to_list nomenclature
          # For example, if channel is "posts:1", and channels is ["posts:1-2", "posts:2-3", "posts:1-3"],
          # this method will return ["posts:1-2", "post:1-3"].
          # channel attr must have parts separated by ":" and must have at least 2 parts
          # channels must have parts separated by ":" and must have at least 2 parts, and in the last part
          # which represents the identifiers, they must be separated by "-"
          def find_matching_channels(channel, channels)
            parts = channel.split(":")
            return [] if parts.length == 1

            id = parts.pop
            base_channel = parts.join(":")

            channels.filter_map do |ch|
              if ch.start_with?(base_channel)
                ids = ch.split(":").last
                ch if ids != ch && ids.split("-").include?(id)
              end
            end
          end
        end
    end
  end
end
