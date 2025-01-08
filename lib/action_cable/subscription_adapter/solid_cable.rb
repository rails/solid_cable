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
        @listener = nil
      end

      def broadcast(channel, payload)
        ::SolidCable::Message.broadcast(channel, payload)

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
          Stop = Class.new(Exception)

          def initialize(event_loop)
            super()

            @event_loop = event_loop

            # Critical section begins with 0 permits. It can be understood as
            # being "normally held" by the listener thread. It is released
            # for specific sections of code, rather than acquired.
            @critical = Concurrent::Semaphore.new(0)

            @thread = Thread.new do
              listen
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
            attr_writer :last_id

            def last_id
              @last_id ||= ::SolidCable::Message.maximum(:id) || 0
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
            end

            def with_polling_volume
              if ::SolidCable.silence_polling? && ActiveRecord::Base.logger
                ActiveRecord::Base.logger.silence { yield }
              else
                yield
              end
            end

            def wake_up
              interrupt
            end

            SELF_PIPE_BLOCK_SIZE = 11

            def interrupt
              self_pipe[:writer].write_nonblock(".")
            rescue Errno::EAGAIN, Errno::EINTR
              # Ignore writes that would block and retry
              # if another signal arrived while writing
              retry
            end

            def interruptible_sleep(time)
              if time > 0 && self_pipe[:reader].wait_readable(time)
                loop { self_pipe[:reader].read_nonblock(SELF_PIPE_BLOCK_SIZE) }
              end
            rescue Errno::EAGAIN, Errno::EINTR
            end

            # Self-pipe for signal-handling (http://cr.yp.to/docs/selfpipe.html)
            def self_pipe
              @self_pipe ||= create_self_pipe
            end

            def create_self_pipe
              reader, writer = IO.pipe
              { reader: reader, writer: writer }
            end
        end
    end
  end
end
